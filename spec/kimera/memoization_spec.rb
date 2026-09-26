# frozen_string_literal: true

require "kimera/memoization"

RSpec.describe(Kimera::Memoization) do
  def reasons(source)
    described_class.ranges(source).map(&:reason)
  end

  def covers?(source, snippet)
    at = source.index(snippet)
    finish = at + snippet.length
    described_class.ranges(source).any? { |r| r.contains?(at, finish) }
  end

  def find(node, klass)
    return node if node.is_a?(klass)
    node.compact_child_nodes.filter_map { |child| find(child, klass) }.first
  end

  describe Kimera::Memoization::Range do
    subject(:range) { described_class.new(10, 20, "memoized") }

    it "includes a span strictly inside the range" do
      expect(range.contains?(12, 18)).to(be(true))
    end

    it "is inclusive at the low boundary (start == start_offset)" do
      expect(range.contains?(10, 18)).to(be(true))
    end

    it "is inclusive at the high boundary (finish == end_offset)" do
      expect(range.contains?(12, 20)).to(be(true))
    end

    it "is inclusive at both boundaries simultaneously" do
      expect(range.contains?(10, 20)).to(be(true))
    end

    it "rejects a span starting before the range" do
      expect(range.contains?(9, 20)).to(be(false))
    end

    it "rejects a span ending after the range" do
      expect(range.contains?(10, 21)).to(be(false))
    end

    it "rejects when only the start is inside (both conditions required)" do
      expect(range.contains?(10, 25)).to(be(false))
    end

    it "rejects when only the finish is inside (both conditions required)" do
      expect(range.contains?(5, 20)).to(be(false))
    end
  end

  it "returns [] for source that fails to parse" do
    expect(described_class.ranges("def broken(")).to(eq([]))
  end

  it "returns [] even when a failed parse's partial AST contains memoization" do
    expect(described_class.ranges("@x ||= 1\ndef broken(")).to(eq([]))
  end

  it "returns [] when there is no memoization" do
    expect(described_class.ranges("def m(a, b)\n  a > b\nend\n")).to(eq([]))
  end

  describe "||= or-write forms" do
    it "taints an instance-variable ||=", :aggregate_failures do
      src = "def m\n  @x ||= compute(a > b)\nend\n"
      expect(reasons(src)).to(eq(["memoized via ||="]))
      expect(covers?(src, "a > b")).to(be(true))
    end

    it "taints a class-variable ||=" do
      src = "def m\n  @@x ||= heavy\nend\n"
      expect(reasons(src)).to(eq(["memoized via ||="]))
    end

    it "taints a global-variable ||=" do
      src = "def m\n  $x ||= heavy\nend\n"
      expect(reasons(src)).to(eq(["memoized via ||="]))
    end

    it "does not taint a local-variable ||= (recomputed every call)", :aggregate_failures do
      src = "def m(a, b)\n  x ||= compute(a > b)\n  x\nend\n"
      expect(reasons(src)).to(eq([]))
      expect(covers?(src, "a > b")).to(be(false))
    end

    it "does not taint a local-variable `x = x || EXPR`", :aggregate_failures do
      src = "def m(a, b)\n  x = x || compute(a > b)\n  x\nend\n"
      expect(reasons(src)).to(eq([]))
      expect(covers?(src, "a > b")).to(be(false))
    end
  end

  describe "constant assignment" do
    it "taints a plain constant write", :aggregate_failures do
      src = "class C\n  RATE = compute(a > b)\nend\n"
      expect(reasons(src)).to(eq(["constant assignment (computed once)"]))
      expect(covers?(src, "a > b")).to(be(true))
    end

    it "taints a constant-path write" do
      src = "Foo::BAR = compute(1)\n"
      expect(reasons(src)).to(eq(["constant assignment (computed once)"]))
    end

    # A method body inside the constant's block still runs per call.
    it "does not taint a method body nested inside a Struct constant" do
      src = "Pair = Struct.new(:a, :b) do\n  def ok?\n    a >= b\n  end\nend\n"
      expect(covers?(src, "a >= b")).to(be(false))
    end

    it "still taints the load-once part outside a nested def", :aggregate_failures do
      src = "T = build(a > b) do\n  def m\n    c > d\n  end\nend\n"
      expect(covers?(src, "a > b")).to(be(true))
      expect(covers?(src, "c > d")).to(be(false))
    end

    it "handles a body-less method nested inside a constant assignment" do
      src = "T = build do\n  def nop; end\nend\n"
      expect(reasons(src)).to(eq(["constant assignment (computed once)"]))
    end
  end

  describe "self-or-write `x = x || EXPR`" do
    it "taints `@x = @x || EXPR`", :aggregate_failures do
      src = "def m\n  @x = @x || compute(a > b)\nend\n"
      expect(reasons(src)).to(eq(["memoized via `x = x || ...`"]))
      expect(covers?(src, "a > b")).to(be(true))
    end

    it "ignores `@x = @y || EXPR` (different name)" do
      src = "def m\n  @x = @y || compute(a > b)\nend\n"
      expect(reasons(src)).to(eq([]))
    end

    it "ignores `@x = something_else` (not an or-node)" do
      src = "def m\n  @x = compute(a > b)\nend\n"
      expect(reasons(src)).to(eq([]))
    end

    it "ignores `@x = other_var || EXPR` (left side is not a read of @x)" do
      src = "def m\n  @x = 1 || compute(a > b)\nend\n"
      expect(reasons(src)).to(eq([]))
    end

    it "requires the or-left to be the matching read node, not merely same-named" do
      result = Prism.parse("def m\n  @x = @@x || compute(1)\nend\n")
      write = find(result.value, Prism::InstanceVariableWriteNode)
      allow(write.value.left).to(receive(:name).and_return(:@x))
      expect(described_class.cached(write)).to(be_nil)
    end
  end

  describe "non-node and value-less inputs" do
    it "visit tolerates a non-node argument", :aggregate_failures do
      ranges = []
      expect(described_class.visit(:not_a_node, ranges)).to(be_nil)
      expect(ranges).to(eq([]))
    end

    it "holes returns the accumulator untouched for a non-node" do
      expect(described_class.holes(:not_a_node)).to(eq([]))
    end

    it "taints nothing for an or-write node without a value" do
      # Skips Prism's constructor, which requires args.
      fake = Class.new(Prism::InstanceVariableOrWriteNode) do
        def initialize; end

        # stubs a valueless node on purpose
        def value; end
      end.new
      expect(described_class.taint(fake)).to(be_nil)
    end

    it "taints nothing for a constant write without a value" do
      fake = Class.new(Prism::ConstantWriteNode) do
        def initialize; end

        # stubs a valueless node on purpose
        def value; end
      end.new
      expect(described_class.taint(fake)).to(be_nil)
    end
  end
end
