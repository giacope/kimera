# frozen_string_literal: true

require "kimera/default_removal"
require "kimera/registry/builder"

# Which `default => required` mutants a warm guard can stand in for. The guard
# keeps the parameter optional and raises from its default, so it matches the
# real signature only when that change binds the same arguments and skips no
# default the real arity check would never run.
RSpec.describe(Kimera::DefaultRemoval) do
  def scan(source)
    operators = Kimera::Operators.build(keys: ["default_argument"])
    Kimera::RegistryScan.new(operators: operators).source(source, file: "x.rb")
  end

  def verdicts(source)
    scan(source).points.to_h { |point| [point.original_source, point.safe? ? :warm : point.unsafe_reason] }
  end

  it "never emits a removal whose signature would not parse" do
    expect(verdicts("def m(a = 1, b = 2, c = 3)\nend\ndef n(a, b = 1, c = 2, *rest)\nend\n").keys)
      .to(eq(["a = 1", "c = 3", "b = 1"]))
  end

  it "runs a removal warm only where it binds the same arguments", :aggregate_failures do
    expect(verdicts("def m(a = 1, b = 2)\nend\n"))
      .to(eq("a = 1" => :warm, "b = 2" => described_class::REBINDS))
    expect(verdicts("def m(a, b = 2, *rest)\nend\n")).to(eq("b = 2" => :warm))
    expect(verdicts("f = ->(a = 1, b = 2) {}\n").values).to(eq([:warm, described_class::REBINDS]))
  end

  it "sends a block's positional removals to reload, since an omitted block argument is nil" do
    expect(verdicts("def m\n  each { |a, b = 2, c: 3| a }\nend\n"))
      .to(eq("b = 2" => described_class::BLOCK, "c: 3" => :warm))
  end

  it "runs a keyword removal warm only after inert defaults", :aggregate_failures do
    inert = "def m(a, b = 2, s = \"s\", t = a, u = nil, v = 1.5, w = true, y = false, z = :k, c: 3)\nend\n"
    expect(verdicts(inert)["c: 3"]).to(eq(:warm))
    expect(verdicts("def m(a, b = a.to_s, c: 3)\nend\n")["c: 3"]).to(eq(described_class::REORDERS))
    expect(verdicts("def m(a, k: compute, c: 3)\nend\n"))
      .to(eq("k: compute" => :warm, "c: 3" => described_class::REORDERS))
  end

  # Prism recovers a tree from broken source; its signatures aren't trusted.
  it "finds nothing in source that does not parse, or in methods without parameters", :aggregate_failures do
    broken = "def m(a = 1, b = 2, c = 3, d: a.to_s, e: 1)\n  x =\nend\n"
    expect([described_class.exemptions(broken), described_class.ranges(broken)]).to(eq([[], []]))
    expect([described_class.exemptions("def m; end"), described_class.ranges("x { 1 }")]).to(eq([[], []]))
  end
end
