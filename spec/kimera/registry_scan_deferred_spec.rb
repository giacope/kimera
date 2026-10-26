# frozen_string_literal: true

require "kimera/registry/builder"

# A block whose body runs on each call (define_method, lambda, proc,
# Proc.new) is mutated like a method body; any other block outside a method
# is reported as not mutated, never silently skipped.
RSpec.describe(Kimera::RegistryScan) do
  def scan(source) = described_class.new.source(source, file: "widget.rb")

  def lines(registry) = registry.points.select(&:safe?).map { |point| point.location.start_line }.uniq

  it "mutates define_method and define_singleton_method bodies warm, under the method's name", :aggregate_failures do
    registry = scan(<<~RUBY)
      class Widget
        define_method(:tiny?) { size < 3 }
        define_singleton_method("valid?") do |value|
          value > 0
        end
      end
    RUBY
    expect(lines(registry)).to(eq([2, 4]))
    expect(registry.points.map(&:method_name).uniq).to(eq(%w[tiny? valid?]))
  end

  it "mutates a define_method body inside a class-level loop, leaving the loop unreported", :aggregate_failures do
    registry = scan("class W\n  %i[a b].each do |n|\n    define_method(n) { |v| v > 1 }\n  end\nend\n")
    expect(lines(registry)).to(eq([3]))
    expect(registry.points.map(&:method_name).uniq).to(eq([nil]))
    expect(registry.unmutated).to(be_empty)
  end

  it "mutates lambda, proc and Proc.new bodies, even assigned to a constant" do
    registry = scan("class W\n  A = lambda { |v| v > 1 }\n  B = proc { |v| v < 2 }\n  C = Proc.new { _1 == 3 }\nend\n")
    expect(lines(registry)).to(eq([2, 3, 4]))
  end

  it "leaves a block given to another call alone, reporting where it is and why", :aggregate_failures do
    registry = scan("class W\n  LIMITS = [5].map { _1 > 1 ? 2 : 1 }\n  rule(:sane) do |size|\n    size > 0\n  end\nend")
    expect(registry.points.select(&:safe?)).to(be_empty)
    expect(registry.unmutated.map { |region| [region.start_line, region.end_line] }).to(eq([[2, 2], [4, 4]]))
    expect(registry.unmutated.map(&:reason).uniq).to(eq([Kimera::Unmutated::BLOCK]))
  end

  it "doesn't report a class-level block that only declares things" do
    expect(scan("class W\n  included do\n    attr_reader :x\n  end\nend\n").unmutated).to(be_empty)
  end

  it "reports a file that does not parse instead of skipping it", :aggregate_failures do
    registry = scan("class Broken\n  def oops(\nend\n")
    expect(registry.points).to(be_empty)
    region = registry.unmutated.first
    expect([region.file, region.start_line, region.end_line]).to(eq(["widget.rb", 1, 3]))
    expect(region.reason).to(start_with(Kimera::Unmutated::UNPARSED))
  end

  it "keeps its regions through the registry's JSON" do
    registry = scan("class W\n  X = [1].map { |n| n > 0 }\nend\n")
    expect(Kimera::Registry.parse(registry.to_json).unmutated).to(eq(registry.unmutated))
  end

  it "narrows its regions to the changed lines of the files that changed" do
    registry = scan("class W\n  X = [1].map { |n| n > 0 }\n  Y = [2].map { |n| n > 0 }\nend\n")
    expect(registry.narrowed("widget.rb" => Set[3]).unmutated.map(&:start_line)).to(eq([3]))
  end

  it "reports the code of a block inside a class-level block once" do
    registry = scan("class W\n  setup do\n    [1].each do |n|\n      n > 0\n    end\n  end\nend\n")
    expect(registry.unmutated.map { |region| [region.start_line, region.end_line] }).to(eq([[4, 4]]))
  end

  it "reports every line of a skipped node in a class-level block as one run" do
    registry = scan("class W\n  setup do\n    @mode = @size > 1 ?\n      1 : 2\n  end\nend")
    expect(registry.unmutated.map { |region| [region.start_line, region.end_line] }).to(eq([[3, 4]]))
  end

  # A lambda in the block is mutated; what is not mutated is the line beside
  # it, not the block that holds both (R6B1-M3).
  it "reports the lines it skips in a class-level block, not the lines it mutates there", :aggregate_failures do
    registry = scan("class W\n  configure do\n    @limit = -> { 10 > 5 }\n    @mode = @limit.call ? 1 : 2\n  end\nend")
    expect(lines(registry)).to(eq([3]))
    expect(registry.unmutated.map { |region| [region.start_line, region.end_line] }).to(eq([[4, 4]]))
  end

  it "takes a method defined from a block argument as no block body" do
    call = Prism.parse("define_method(:x, &handler)").value.statements.body.first
    expect(Kimera::Deferral.new(call).block).to(be_nil)
  end
end
