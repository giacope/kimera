# frozen_string_literal: true

require "kimera/memo_guard"

RSpec.describe(Kimera::MemoGuard) do
  def exemptions(source) = described_class::Source.new(source).exemptions.map { [it.location.slice, it.operator] }

  it "exempts the condition of a value guard whose ivar the method then assigns" do
    source = "def m\n  return @x if @x\n\n  @x = compute\nend\n"
    expect(exemptions(source)).to(eq([["return @x if @x", "conditional"]]))
  end

  it "exempts both the condition and the flag of a run-once guard" do
    source = "class C\n  def m\n    return if @done\n    @done = true\n    work\n  end\nend\n"
    expect(exemptions(source)).to(eq([["return if @done", "conditional"], %w[true boolean_literal]]))
  end

  it "recognizes a guard written as a full if" do
    source = "def m\n  if @x\n    return @x\n  end\n  @x = compute\nend\n"
    expect(exemptions(source).map(&:last)).to(eq(["conditional"]))
  end

  it "exempts nothing that isn't a memo", :aggregate_failures do
    {
      "a value guard the method never assigns" => "def m\n  return @x if @x\nend\n",
      "a guard returning another ivar" => "def m\n  return @y if @x\n  @x = true\nend\n",
      "a state check" => "def m\n  return if @stopped\n  work\nend\n",
      "a flag set to false" => "def m\n  return if @x\n  @x = false\nend\n",
      "a flag on another ivar" => "def m\n  return if @x\n  @y = true\nend\n",
      "a guard that is not the first statement" => "def m\n  prepare\n  return @x if @x\n  @x = compute\nend\n",
      "a guard with an else" => "def m\n  if @x\n    return @x\n  else\n    warn\n  end\n  @x = compute\nend\n",
      "a guarded statement that isn't a return" => "def m\n  warn if @x\n  @x = true\nend\n",
      "a defined? guard, which Conditional skips itself" => "def m\n  return @x if defined?(@x)\n  @x = compute\nend\n",
      "a method with no body" => "def m; end\n",
      "a method whose body rescues" => "def m\n  return @x if @x\n  @x = compute\nrescue\n  nil\nend\n",
      "source that fails to parse" => "def m\n  return @x if @x\n  @x = compute\nend\ndef broken("
    }.each { |shape, source| expect(exemptions(source)).to(eq([]), shape) }
  end
end
