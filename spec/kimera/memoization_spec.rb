# frozen_string_literal: true

require "kimera/memoization"

RSpec.describe(Kimera::Memoization) do
  def reasons(source)
    described_class.new(source).ranges.map(&:reason)
  end

  def covers?(source, snippet)
    at = source.index(snippet)
    finish = at + snippet.length
    described_class.new(source).ranges.any? { |r| r.contains?(at, finish) }
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

    # A keyed cache is memoization too (D6): each key's value is computed once.
    it "taints a keyed cache's ||= on an instance, class or global variable, or a memoized hash", :aggregate_failures do
      %w[@cache @@cache $cache (@cache||={})].each do |cache|
        line = "#{cache}[key] ||= compute(a > b)"
        code = "def m(key)\n  #{line}\nend\n"
        expect(reasons(code)).to(include("memoized via `cache[key] ||=`"), line)
        expect(covers?(code, "a > b")).to(be(true), line)
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

    # A method body inside the constant's block still runs per call.
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

    it "requires the or-left to be the matching read node, not merely same-named" do
      result = Prism.parse("def m\n  @x = @@x || compute(1)\nend\n")
      write = find(result.value, Prism::InstanceVariableWriteNode)
      allow(write.value.left).to(receive(:name).and_return(:@x))
      expect(described_class.new("").__send__(:cached, write)).to(be_nil)
    end
  end

  describe "non-node and value-less inputs" do
    it "visit tolerates a non-node argument" do
      expect(described_class.new("").__send__(:visit, :not_a_node)).to(eq([]))
    end

    it "holes finds none in a non-node" do
      expect(described_class.new("").__send__(:holes, :not_a_node)).to(eq([]))
    end

    it "taints nothing for an or-write node without a value" do
      # Skips Prism's constructor, which requires args.
      fake = Class.new(Prism::InstanceVariableOrWriteNode) do
        def initialize; end

        # stubs a valueless node on purpose
        def value; end
      end.new
      expect(described_class.new("").__send__(:taint, fake)).to(be_nil)
    end

    it "taints nothing for a constant write without a value" do
      fake = Class.new(Prism::ConstantWriteNode) do
        def initialize; end

        # stubs a valueless node on purpose
        def value; end
      end.new
      expect(described_class.new("").__send__(:taint, fake)).to(be_nil)
    end
  end
end
