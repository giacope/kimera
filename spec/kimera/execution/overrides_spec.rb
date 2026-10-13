# frozen_string_literal: true

require "fileutils"
require "kimera/execution/overrides"
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
    overrides = described_class.new(own, source)
    overlay(overrides)
    expect([OverridesOrder.new.total, OverridesOrder.make, OverridesOrder.build]).to(eq([2, :later, :later]))
    expect(overrides.displaced.map { |held| [held.name, held.definition.source_location.first] })
      .to(contain_exactly([:total, own], [:make, own], [:build, own]))
  end

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
    code = "class OverridesMissing\n  def gone = 1\nend\n\ndef OverridesOrder.other = 1\n[1].each { def inside = 1 }\n"
    expect(described_class.new(own, code).keep { :done }).to(eq(:done))
  end

  it "reads nothing from a source that does not parse" do
    overrides = described_class.new(own, "class Broken\n  def oops(\nend\n")
    overrides.keep { :done }
    expect(overrides.displaced).to(be_empty)
  end
end
