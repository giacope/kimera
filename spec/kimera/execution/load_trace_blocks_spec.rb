# frozen_string_literal: true

require "fileutils"
require "kimera/execution/definitions"
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

  it "knows which in-scope files the suite loaded" do
    other = File.join(dir, "other.rb").tap { |path| File.write(path, "class LoadBlocksOther; end\n") }
    scan = Kimera::RegistryScan.new(root: dir).build([file, other])
    watched = described_class.new(scan, dir)
    watched.record { load(file) }
    expect(watched.loaded?("blocks.rb")).to(be(true))
    expect(watched.loaded?("other.rb")).to(be(false))
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
end
