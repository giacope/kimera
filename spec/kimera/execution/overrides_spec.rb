# frozen_string_literal: true

require "fileutils"
require "kimera/execution/overrides"
require "kimera/registry/builder"
require "tmpdir"

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

  def inside
    stub_const("OverridesOrder", Class.new)
    yield
  ensure
    FileUtils.remove_entry(dir)
  end

  def evaluate(target, code, file) = target.class_eval(code, file)

  def boot
    evaluate(Object, source, own)
    evaluate(OverridesOrder, redefined, later)
  end

  def overlay(overrides) = overrides.keep { evaluate(Object, source.gsub(":own", ":again"), own) }

  def booted = boot.then { overlay(described_class.new(own, source)) }

  def holders = { total: OverridesOrder, make: OverridesOrder.singleton_class, build: OverridesOrder.singleton_class }

  def replaced(displaced, **holders)
    holders.to_h do |name, holder|
      [name, displaced.flat_map { |held| held.replacing(name, [holder]) }.map { |kept| kept.source_location.first }]
    end
  end

  it "puts back what a later file defined, and hands over the overlaid version", :aggregate_failures do
    inside do
      _, displaced = booted
      expect([OverridesOrder.new.total, OverridesOrder.make, OverridesOrder.build]).to(eq([2, :later, :later]))
      expect(replaced(displaced, **holders)).to(eq(total: [own], make: [own], build: [own]))
    end
  end

  def tallying = "class OverridesOrder\n  def OverridesTally.make = :tally\nend\n"

  it "puts back no method of the class's own for one the file defines on another object" do
    inside do
      evaluate(OverridesOrder, "def self.make = :later", later)
      _, displaced = described_class.new(own, tallying).keep { evaluate(OverridesOrder, "def self.make = :own", own) }
      expect([OverridesOrder.make, displaced]).to(eq([:own, []]))
    end
  end

  describe "a kept method's revisit" do
    def points
      text = "class Revisited\n  def total = a > b\n\n\n\n\n\n\n\n  def kept = a > b\nend\n"
      Kimera::RegistryScan.new.source(text, file: "x.rb").to_h.fetch("x.rb")
    end

    def revisits(held, found = points)
      found.tap { |each| held.each { it.revisit!(each) } }.map { it.reasons(Kimera::Reason.revisiting).first }
    end

    def marked(held)
      text = "class Revisited\n#{(2..10).map { |line| "  def at#{line} = a > b\n" }.join}end\n"
      found = Kimera::RegistryScan.new.source(text, file: "x.rb").to_h.fetch("x.rb")
      revisits(held, found).each_with_index.filter_map { |reason, index| index + 2 if reason }
    end

    def spanning(lines) = Data.define(:start_line, :end_line).new(lines.first, lines.last)

    def kept(lines) = described_class::Held.new(nil, nil, :public, spanning(lines))

    it "judges again the mutants on the lines of a method another file keeps", :aggregate_failures do
      inside do
        _, displaced = booted
        expect(marked(displaced)).to(eq([2, 4, 7]))
        expect(revisits(displaced)).to(eq([described_class::Held::WRAPPED, nil]))
      end
    end

    it "leaves a point already set aside, and every point when nothing is kept", :aggregate_failures do
      found = points.tap { |each| each.first.mark!(Kimera::Reason.unsafe("set aside")) }
      expect(revisits([kept(2..10)], found)).to(eq([nil, described_class::Held::WRAPPED]))
      expect(revisits([kept(3..9)])).to(eq([nil, nil]))
    end
  end

  it "hands over only what the overlay redefined" do
    inside do
      boot
      _, displaced = described_class.new(own, source).keep { evaluate(OverridesOrder, "def total = 9", own) }
      expect([displaced.size, replaced(displaced, total: OverridesOrder)]).to(eq([1, { total: [own] }]))
    end
  end

  describe "a later file's top-level method" do
    def topped
      inside do
        { own => :own, later => :later }.each { |file, value| evaluate(Object, "def overrides_top = :#{value}", file) }
        yield
      end
    ensure
      Object.class_eval { remove_method(:overrides_top) }
    end

    it "is kept" do
      topped do
        overrides = described_class.new(own, "def overrides_top = :own\n")
        _, displaced = overrides.keep { evaluate(Object, "def overrides_top = :again", own) }
        expect([overrides_top, displaced.size, replaced(displaced, overrides_top: Object)])
          .to(eq([:later, 1, { overrides_top: [own] }]))
      end
    end
  end

  def quietly
    overrides = described_class.new(own, source)
    -> { verbosely { overrides.keep { silently { evaluate(Object, source, own) } } } }
  end

  it "puts a method back without a warning under $VERBOSE" do
    inside do
      boot
      expect(&quietly).not_to(output.to_stderr)
    end
  end

  def verbosely
    previous = $VERBOSE
    $VERBOSE = true
    yield
  ensure
    $VERBOSE = previous
  end

  def silently(&) = Kimera::Warnings.silenced.during(&)

  it "lets the overlay redefine what only its own file defined" do
    inside do
      booted
      expect(OverridesOrder.new.kept).to(eq(:again))
    end
  end

  def privately = boot.then { evaluate(OverridesOrder, "private def total = 3", later) }

  it "keeps a later file's private method private" do
    inside do
      privately
      overlay(described_class.new(own, source))
      expect(OverridesOrder.private_method_defined?(:total)).to(be(true))
    end
  end

  def unresolved
    "class OverridesMissing\n  def gone = 1\nend\n\ndef OverridesOrder.other = 1\n" \
      "[1].each { def inside = 1 }\n" \
      "class OverridesOrder\nend\nclass OverridesOrder\n  class << self\n  end\nend\n"
  end

  it "skips a class it can't resolve, a def on another receiver, and a block's defs" do
    inside do
      expect(described_class.new(own, unresolved).keep { :done }.first).to(eq(:done))
    end
  end

  it "reads nothing from a source that does not parse" do
    inside do
      expect(described_class.new(own, "class Broken\n  def oops(\nend\n").keep { :done }).to(eq([:done, []]))
    end
  end

  describe Kimera::Execution::Origin do
    def canonical(path) = described_class.new(path).canonical

    def linked
      File.symlink(dir, File.join(dir, "linked"))
      File.join(dir, "linked", "order.rb").tap { own }
    end

    it "names a file by its real path, and anything else as given", :aggregate_failures do
      inside do
        expect(canonical(linked)).to(eq(File.realpath(own)))
        expect(canonical("/no/such/file.rb")).to(eq("/no/such/file.rb"))
        expect(canonical(nil)).to(be_nil)
      end
    end
  end
end
