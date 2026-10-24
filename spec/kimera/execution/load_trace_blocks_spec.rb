# frozen_string_literal: true

require "fileutils"
require "kimera/execution/definitions"
require "kimera/execution/isolated_plan"
require "kimera/execution/load_trace"
require "kimera/execution/verdicts"
require "kimera/registry/builder"
require "tmpdir"

# R3K2: a lambda a class body calls to build a constant ran only while the
# file loaded, before warm coverage starts, and read as "no covering test".
RSpec.describe(Kimera::Execution::LoadTrace, :aggregate_failures) do
  let(:source) do
    <<~RUBY
      class LoadBlocks
        env_int = lambda do |val|
          val if val >= 0
        end
        MAX = env_int.call(4096)
        idle = ->(n) { n > 1 }
        BUILT = Struct.new(:a) do
          def big? = a > 9
        end
        [1].each { |n| N = n + 1 }
      end
    RUBY
  end

  let(:dir) { Dir.mktmpdir }
  let(:file) { File.join(dir, "blocks.rb").tap { |path| File.write(path, source) } }
  let(:registry) { Kimera::RegistryScan.new(root: dir).build([file]) }
  let(:trace) { described_class.new(registry, dir) }

  before { stub_const("LoadBlocks", Class.new) }

  after { FileUtils.remove_entry(dir) }

  def point(text) = registry.points.find { |found| found.original_source == text }

  def loaded(coverage = {})
    trace.record { load(file) }
    trace.quarantine!(coverage)
  end

  it "sends the uncovered mutants of a block that ran while loading to the isolated tier" do
    loaded
    expect(point("val >= 0")).to(have_attributes(safe?: false, unsafe_reason: Kimera::MutationPoint::LOAD_REASON))
  end

  it "leaves a lambda that did not run, and a method a running block only defines" do
    loaded
    expect(point("n > 1")).to(have_attributes(unsafe_reason: nil, revisit: nil))
    expect(point("a > 9")).to(have_attributes(unsafe_reason: nil, revisit: nil))
  end

  it "judges again a covered point of a block that ran while loading" do
    loaded(point("val >= 0").ids.to_h { |id| [id, ["t1"]] })
    expect(point("val >= 0").revisit).to(eq(Kimera::MutationPoint::BOOT_REASON))
  end

  it "ignores what runs outside the in-scope files while the suite loads" do
    trace.record { load(file) && [1].each { |n| n + 1 } }
    expect { trace.quarantine!({}) }.not_to(raise_error)
    expect(point("val >= 0").unsafe_reason).to(eq(Kimera::MutationPoint::LOAD_REASON))
  end

  # A macro that defines a method with def at load: the method holds what
  # the original macro defined, which the warm overlay cannot replace.
  # A file whose class body runs a macro that defines a method with def.
  def macro_file
    File.join(dir, "nested.rb").tap do |path|
      File.write(path, "class LoadBlocks\n  def self.make\n    def built(a) = a > 1\n  end\n  make\nend\n")
    end
  end

  # A scan of the files, and a trace that recorded loading some of them.
  def recorded(files, loads)
    scan = Kimera::RegistryScan.new(root: dir).build(files)
    [scan, described_class.new(scan, dir).tap { |watched| watched.record { loads.each { |path| load(path) } } }]
  end

  it "keeps a method a load-time macro defines inside the macro's span" do
    nested = macro_file
    scan, watched = recorded([nested], [nested])
    watched.quarantine!({})
    expect(scan.points.find { |found| found.original_source == "a > 1" }.unsafe_reason)
      .to(eq(Kimera::MutationPoint::LOAD_REASON))
  end

  it "knows which in-scope files the suite loaded" do
    other = File.join(dir, "other.rb").tap { |path| File.write(path, "class LoadBlocksOther; end\n") }
    _, watched = recorded([file, other], [file])
    expect([watched.loaded?("blocks.rb"), watched.loaded?("other.rb")]).to(eq([true, false]))
  end

  it "knows a file the suite required, though none of its code ran under the trace" do
    plain = File.join(dir, "plain.rb").tap { |path| File.write(path, "LoadBlocks::PLAIN = ->(a) { a > 1 }\n") }
    scan = Kimera::RegistryScan.new(root: dir).build([plain])
    watched = described_class.new(scan, dir)
    watched.record { require(plain) }
    expect(watched.loaded?("plain.rb")).to(be(true))
  end

  describe Kimera::Execution::Definitions do
    def only?(source) = described_class.new(source).only?

    it "holds a file that only defines and requires" do
      defining = "require \"x\"\nrequire_relative \"y\"\nautoload :Z, \"z\"\n" \
        "module A; end\nclass B < A; end\nC = 1\nA::D ||= 2\n"
      expect(only?(defining)).to(be(true))
      expect(only?("")).to(be(true))
    end

    # R5-KL4: a class body runs as it loads (`@limit = 100`, `after Parser`).
    it "holds a class or module body only of definitions, constants, requires and declarations" do
      nested = "module A\n  require \"x\"\n  B = 1\n  class C < A::D\n    def c = 1\n    def self.d = 2\n  end\n  " \
        "class << self\n    def e = 3\n  end\nend\n"
      declared = "class P\n  attr_reader :a\n  alias b a\n  alias_method :c, :a\n  private\n  private def d = 1\nend\n"
      expect([only?(nested), only?(declared)]).to(eq([true, true]))
    end

    it "rejects a class or module body that runs code as it loads" do
      running = [
        "class Q\n  include Comparable\nend\n", "class Q\n  private(*NAMES)\nend\n",
        "module Core\n  @limit = 100\n  def self.plugin? = true\nend\n",
        "class E\n  class I\n    after Parser\n  end\nend\n",
        "module I18n\n  begin\n    require \"oj\"\n  rescue LoadError\n    nil\n  end\nend\n"
      ]
      expect(running.map { |source| only?(source) }.uniq).to(eq([false]))
    end

    it "rejects a file that assigns or calls at its top level" do
      expect(only?("SETTINGS[:greet] = -> { 1 }\n")).to(be(false))
      expect(only?("Thredded.user_path = 1\n")).to(be(false))
      expect(only?("puts 1\n")).to(be(false))
      expect(only?("x.require \"y\"\n")).to(be(false))
    end
  end

  # K3-7: a file the suite never loads is uncovered, and never evaluated.
  it "reports a never-loaded point uncovered, not isolated, and never reloads it" do
    found = point("val >= 0")
    found.unloaded!
    result = Kimera::Execution::Verdicts.new(registry).quarantine(found.ids.first)
    expect(result).to(have_attributes(status: :no_coverage, detail: Kimera::MutationPoint::NEVER_LOADED))
    expect(found.reloadable?).to(be(false))
  end

  it "gives a never-loaded point no test to run in a mirror" do
    found = point("val >= 0")
    plan = Kimera::Execution::IsolatedPlan.new(
      registry: registry, root: dir, tests: ["t1"], framework: "rspec", test_files: [], coverage: {}
    )
    steps = [-> {}, -> { found.unsafe!(Kimera::MutationPoint::LOAD_REASON) }, -> { found.unloaded! }]
    expect(steps.map { |step| step.call.then { plan.tests(found.ids.first, found) } }).to(eq([nil, ["t1"], nil]))
  end
end
