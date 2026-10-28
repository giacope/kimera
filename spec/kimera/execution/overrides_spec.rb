# frozen_string_literal: true

require "fileutils"
require "kimera/execution/overrides"
require "kimera/registry/builder"
require "tmpdir"

# Overlaying a file evaluates it again; a method a later file redefined must
# keep the later definition.
RSpec.describe(Kimera::Execution::Overrides) do
  let(:dir) { Dir.mktmpdir }
  let(:own) { File.join(dir, "order.rb").tap { |file| File.write(file, "") } }
  let(:later) { File.join(dir, "tax.rb").tap { |file| File.write(file, "") } }
  let(:source) do
    <<~RUBY
      class OverridesOrder
        def total = 1

        def self.make = :own

        class << self
          def build = :own
        end

        def kept = :own
      end
    RUBY
  end
  let(:redefined) { "def total = 2\ndef self.make = :later\nclass << self; def build = :later; end" }

  before { stub_const("OverridesOrder", Class.new) }

  after { FileUtils.remove_entry(dir) }

  def evaluate(target, code, file) = target.class_eval(code, file)

  def boot
    evaluate(Object, source, own)
    evaluate(OverridesOrder, redefined, later)
  end

  def overlay(overrides) = overrides.keep { evaluate(Object, source.gsub(":own", ":again"), own) }

  it "puts back what a later file defined, and hands over the overlaid version", :aggregate_failures do
    boot
    _, displaced = overlay(described_class.new(own, source))
    expect([OverridesOrder.new.total, OverridesOrder.make, OverridesOrder.build]).to(eq([2, :later, :later]))
    expect(displaced.map { |held| [held.name, held.definition.source_location.first] })
      .to(contain_exactly([:total, own], [:make, own], [:build, own]))
  end

  # R6B4-M7: a memoizer in another file (unparser's Adamantium `memoize`)
  # replaces the method with one that calls the original it captured at load,
  # so the overlaid method is never reached warm.
  describe "a kept method's revisit" do
    def points
      text = "class Revisited\n  def total = a > b\n\n\n\n\n\n\n\n  def kept = a > b\nend\n"
      Kimera::RegistryScan.new.source(text, file: "x.rb").at("x.rb")
    end

    def revisits(held, found = points) = found.tap { |each| held.each { it.revisit!(each) } }.map(&:revisit)

    def spanning(lines) = Data.define(:start_line, :end_line).new(lines.first, lines.last)

    def kept(lines) = described_class::Held.new(nil, :total, nil, :public, spanning(lines))

    it "judges again the mutants on the lines of a method another file keeps", :aggregate_failures do
      boot
      _, displaced = overlay(described_class.new(own, source))
      expect(displaced.map { |held| held.span.start_line }).to(contain_exactly(2, 4, 7))
      expect(revisits(displaced)).to(eq([described_class::WRAPPED, nil]))
    end

    it "leaves a point already set aside, and every point when nothing is kept", :aggregate_failures do
      found = points.tap { |each| each.first.unsafe!("set aside") }
      expect(revisits([kept(2..10)], found)).to(eq([nil, described_class::WRAPPED]))
      expect(revisits([kept(3..9)])).to(eq([nil, nil]))
    end
  end

  it "hands over only what the overlay redefined" do
    boot
    _, displaced = described_class.new(own, source).keep { evaluate(OverridesOrder, "def total = 9", own) }
    expect(displaced.map(&:name)).to(eq([:total]))
  end

  describe "a later file's top-level method" do
    after { Object.__send__(:remove_method, :overrides_top) }

    it "is kept" do
      { own => :own, later => :later }.each { |file, value| evaluate(Object, "def overrides_top = :#{value}", file) }
      overrides = described_class.new(own, "def overrides_top = :own\n")
      _, displaced = overrides.keep { evaluate(Object, "def overrides_top = :again", own) }
      expect([overrides_top, displaced.map(&:name)]).to(eq([:later, [:overrides_top]]))
    end
  end

  # R4-KL7: dry-types raises on every warning; putting a later file's method back warned "method redefined".
  it "puts a method back without a warning under $VERBOSE" do
    boot
    overrides = described_class.new(own, source)
    quietly = -> { Kimera::Warnings.new(true).during { overrides.keep { silently { evaluate(Object, source, own) } } } }
    expect(&quietly).not_to(output.to_stderr)
  end

  def silently(&) = Kimera::Warnings::SILENCED.during(&)

  it "lets the overlay redefine what only its own file defined" do
    boot
    overlay(described_class.new(own, source))
    expect(OverridesOrder.new.kept).to(eq(:again))
  end

  it "keeps a later file's private method private" do
    boot
    evaluate(OverridesOrder, "private def total = 3", later)
    overlay(described_class.new(own, source))
    expect(OverridesOrder.private_method_defined?(:total)).to(be(true))
  end

  it "skips a class it can't resolve, a def on another receiver, and a block's defs" do
    code = "class OverridesMissing\n  def gone = 1\nend\n\ndef OverridesOrder.other = 1\n" \
      "[1].each { def inside = 1 }\n" \
      "class OverridesOrder\nend\nclass OverridesOrder\n  class << self\n  end\nend\n"
    expect(described_class.new(own, code).keep { :done }.first).to(eq(:done))
  end

  it "reads nothing from a source that does not parse" do
    expect(described_class.new(own, "class Broken\n  def oops(\nend\n").keep { :done }).to(eq([:done, []]))
  end

  describe Kimera::Execution::Origin do
    def canonical(path) = described_class.new(path).canonical

    it "names a file by its real path, and anything else as given", :aggregate_failures do
      File.symlink(dir, File.join(dir, "linked"))
      expect(canonical(File.join(dir, "linked", "order.rb").tap { own })).to(eq(File.realpath(own)))
      expect(canonical("/no/such/file.rb")).to(eq("/no/such/file.rb"))
      expect(canonical(nil)).to(be_nil)
    end
  end
end
