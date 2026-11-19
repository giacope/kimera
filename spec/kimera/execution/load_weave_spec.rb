# frozen_string_literal: true

require "kimera/execution/load_weave"
require "kimera/registry/builder"
require "kimera/runtime"
require "json"
require "tmpdir"

RSpec.describe(Kimera::Execution::LoadWeave, :aggregate_failures) do
  let(:dir) { Dir.mktmpdir("kimera-weave") }
  let(:path) { File.join(dir, "weave_held.rb") }
  let(:registry) { Kimera::RegistryScan.new(root: dir).build([path]) }
  let(:weave) { described_class.new(registry) }

  before { File.write(path, "module WeaveHeld\n  CHECK = ->(n) { n > 10 }\nend\n") }

  after { FileUtils.remove_entry(dir) }

  def forked
    reader, writer = IO.pipe
    pid =
      fork do
        writer.write(JSON.generate(yield))
      ensure
        exit!(0)
      end
    writer.close
    JSON.parse(reader.read).tap { Process.wait(pid) }
  end

  def unwritable
    Class.new do
      def initialize(_registry) = nil

      def synthesize(*) = raise(ArgumentError, "unwritable")
    end
  end

  def asking(asked)
    Class.new do
      define_method(:initialize) { |_registry| nil }
      define_method(:synthesize) do |file, _source|
        asked << file
        raise(ArgumentError, "unwritable")
      end
    end
  end

  def underneath(seen)
    hook = Module.new { define_method(:load_iseq) { |path| (seen << path) && (super(path) if defined?(super)) } }
    RubyVM::InstructionSequence.singleton_class.prepend(hook)
  end

  def handed = { path => "weave_held.rb" }

  def boundary = registry.each.find { |mutant,| mutant.to_s == "> => >=" }.first.to_i

  def flips = [WeaveHeld::CHECK.call(10), Kimera::RUNTIME.during(boundary) { WeaveHeld::CHECK.call(10) }]

  it "guards a file as it first loads, so a lambda a constant took then flips with its mutant" do
    held = forked { weave.during(handed) { require(path) }.then { [flips, weave.woven("weave_held.rb") { [] }] } }
    expect(held.first).to(eq([false, true]))
    expect(held.last).to(include(boundary))
  end

  it "keeps the line every node stood on" do
    expect(forked { weave.during(handed) { require(path) }.then { WeaveHeld::CHECK.source_location } })
      .to(eq([path, 2]))
  end

  it "leaves a file it is not handed, or one loaded after the block, as Ruby loads it" do
    expect(forked { weave.during({}) { load(path) } && flips.last }).to(be(false))
    expect(forked { weave.during(handed) { nil }.then { load(path) && flips.last } }).to(be(false))
    expect(weave.woven("weave_held.rb") { :unwoven }).to(eq(:unwoven))
  end

  def loading(overlays, *paths) = described_class.new(registry, overlays).during(handed) { paths.all? { load(it) } }

  it "asks the overlay about the files it is handed, and no other" do
    other = File.join(dir, "other.rb").tap { |file| File.write(file, "1\n") }
    expect(forked { [].tap { |files| loading(asking(files), other, path) } }).to(eq(["weave_held.rb"]))
  end

  it "loads a file it cannot weave as Ruby does" do
    expect(forked { loading(unwritable, path) && WeaveHeld::CHECK.call(11) }).to(be(true))
  end

  it "hands the files it does not weave to a load_iseq hook prepended before it" do
    seen = forked { [].tap { |paths| underneath(paths) && weave.during({}) { load(path) } } }
    expect(seen).to(eq([path]))
  end
end
