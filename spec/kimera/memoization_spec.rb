# frozen_string_literal: true

require "kimera/registry/memoization"

RSpec.describe(Kimera::Memoization) do
  def reasons(source)
    described_class.new(source).ranges.map(&:to_s)
  end

  def covers?(source, snippet)
    at = source.index(snippet)
    finish = at + snippet.length
    described_class.new(source).ranges.any? { |r| r.reasons(at, finish).any? }
  end

  describe Kimera::Memoization::Range do
    subject(:range) { described_class.new(10, 20, "memoized") }

    it "includes a span strictly inside the range" do
      expect(range.reasons(12, 18)).to(eq(["memoized"]))
    end

    it "is inclusive at the low boundary (start == start_offset)" do
      expect(range.reasons(10, 18)).to(eq(["memoized"]))
    end

    it "is inclusive at the high boundary (finish == end_offset)" do
      expect(range.reasons(12, 20)).to(eq(["memoized"]))
    end

    it "is inclusive at both boundaries simultaneously" do
      expect(range.reasons(10, 20)).to(eq(["memoized"]))
    end

    it "rejects a span starting before the range" do
      expect(range.reasons(9, 20)).to(eq([]))
    end

    it "rejects a span ending after the range" do
      expect(range.reasons(10, 21)).to(eq([]))
    end

    it "rejects when only the start is inside (both conditions required)" do
      expect(range.reasons(10, 25)).to(eq([]))
    end

    it "rejects when only the finish is inside (both conditions required)" do
      expect(range.reasons(5, 20)).to(eq([]))
    end
  end

  it "returns [] for source that fails to parse" do
    expect(described_class.new("def broken(").ranges).to(eq([]))
  end

  it "returns [] even when a failed parse's partial AST contains memoization" do
    expect(described_class.new("@x ||= 1\ndef broken(").ranges).to(eq([]))
  end

  it "returns [] when there is no memoization" do
    expect(described_class.new("def m(a, b)\n  a > b\nend\n").ranges).to(eq([]))
  end

  describe "||= or-write forms" do
    it "taints an instance-variable ||=", :aggregate_failures do
      code = "def m\n  @x ||= compute(a > b)\nend\n"
      expect(reasons(code)).to(eq(["memoized via ||="]))
      expect(covers?(code, "a > b")).to(be(true))
    end

    it "taints a class-variable ||=" do
      code = "def m\n  @@x ||= heavy\nend\n"
      expect(reasons(code)).to(eq(["memoized via ||="]))
    end

    it "taints a global-variable ||=" do
      code = "def m\n  $x ||= heavy\nend\n"
      expect(reasons(code)).to(eq(["memoized via ||="]))
    end

    %w[@cache @@cache $cache (@cache||={})].each do |cache|
      it "taints a keyed cache's ||= on #{cache}", :aggregate_failures do
        code = "def m(key)\n  #{cache}[key] ||= compute(a > b)\nend\n"
        expect(reasons(code)).to(include("memoized via `cache[key] ||=`"))
        expect(covers?(code, "a > b")).to(be(true))
      end
    end

    it "does not taint a keyed ||= on a local hash or a call" do
      %w[cache[key] lookup[key]].each do |target|
        code = "def m(key, cache)\n  #{target} ||= compute(a > b)\nend\n"
        expect(reasons(code)).to(eq([]), target)
      end
    end

    it "does not taint a local-variable ||= (recomputed every call)", :aggregate_failures do
      code = "def m(a, b)\n  x ||= compute(a > b)\n  x\nend\n"
      expect(reasons(code)).to(eq([]))
      expect(covers?(code, "a > b")).to(be(false))
    end

    it "does not taint a local-variable `x = x || EXPR`", :aggregate_failures do
      code = "def m(a, b)\n  x = x || compute(a > b)\n  x\nend\n"
      expect(reasons(code)).to(eq([]))
      expect(covers?(code, "a > b")).to(be(false))
    end
  end

  describe "constant assignment" do
    it "taints a plain constant write", :aggregate_failures do
      code = "class C\n  RATE = compute(a > b)\nend\n"
      expect(reasons(code)).to(eq(["constant assignment (computed once)"]))
      expect(covers?(code, "a > b")).to(be(true))
    end

    it "taints a constant-path write" do
      code = "Foo::BAR = compute(1)\n"
      expect(reasons(code)).to(eq(["constant assignment (computed once)"]))
    end

    it "does not taint a method body nested inside a Struct constant" do
      code = "Pair = Struct.new(:a, :b) do\n  def ok?\n    a >= b\n  end\nend\n"
      expect(covers?(code, "a >= b")).to(be(false))
    end

    it "still taints the load-once part outside a nested def", :aggregate_failures do
      code = "T = build(a > b) do\n  def m\n    c > d\n  end\nend\n"
      expect(covers?(code, "a > b")).to(be(true))
      expect(covers?(code, "c > d")).to(be(false))
    end

    it "handles a body-less method nested inside a constant assignment" do
      code = "T = build do\n  def nop; end\nend\n"
      expect(reasons(code)).to(eq(["constant assignment (computed once)"]))
    end
  end

  describe "self-or-write `x = x || EXPR`" do
    it "taints `@x = @x || EXPR`", :aggregate_failures do
      code = "def m\n  @x = @x || compute(a > b)\nend\n"
      expect(reasons(code)).to(eq(["memoized via `x = x || ...`"]))
      expect(covers?(code, "a > b")).to(be(true))
    end

    it "ignores `@x = @y || EXPR` (different name)" do
      code = "def m\n  @x = @y || compute(a > b)\nend\n"
      expect(reasons(code)).to(eq([]))
    end

    it "ignores `@x = something_else` (not an or-node)" do
      code = "def m\n  @x = compute(a > b)\nend\n"
      expect(reasons(code)).to(eq([]))
    end

    it "ignores `@x = other_var || EXPR` (left side is not a read of @x)" do
      code = "def m\n  @x = 1 || compute(a > b)\nend\n"
      expect(reasons(code)).to(eq([]))
    end

    it "requires the or-left to be the matching read node itself, not one in parentheses" do
      code = "def m\n  @x = (@x) || compute(1)\nend\n"
      expect(reasons(code)).to(eq([]))
    end
  end
end
