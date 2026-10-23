# frozen_string_literal: true

require "kimera/scribe"
require "kimera/synthesis/guardrail_factories"

# Scribe writes a node to stand where another stood in its source: with the
# locals bound there, and with every untouched subtree as it was written.
RSpec.describe(Kimera::Scribe) do
  def tree(source) = Kimera::Scribe.parse(source)

  def find(node, slice)
    return node if node.slice == slice && node.type != :statements_node
    node.compact_child_nodes.lazy.filter_map { |child| find(child, slice) }.first
  end

  # The text Scribe writes for the node `yield` makes of the one at `slice`,
  # to stand where that one stands.
  def written(source, slice)
    root = tree(source)
    original = find(root, slice)
    described_class.new(yield(original)).at(root, original).text
  end

  def listed(node) = tree("[nil]").statements.body.first.copy(elements: [node])

  def read(source) = tree(source).statements.body.first

  describe "locals where a node stands" do
    def locals(source, slice, after: false)
      root = tree(source)
      place = Kimera::Scribe::Place.of(root, find(root, slice))
      (after ? place.after(find(root, slice)) : place).locals.to_a.sort
    end

    it "reads earlier writes, parameters and block parameters, and not later ones" do
      source = "def m(a)\n  b = 1\n  [1].each { |c| a + b + c + d }\n  d = 2\nend\n"
      expect(locals(source, "a + b + c + d")).to(eq(%i[a b c]))
    end

    it "starts over in each definition and class, and binds a write's own name in its value", :aggregate_failures do
      expect(locals("x = 1\ndef m(q) = q + 0\n", "q + 0")).to(eq(%i[q]))
      expect(locals("x = 1\nclass A\n  y = 1\n  def m = :z\nend\n", ":z")).to(eq([]))
      expect(locals("x = 1\nclass A\n  y = 1\n  z = :w\nend\n", ":w")).to(eq(%i[y z]))
      expect(locals("x = x\n", "x")).to(eq(%i[x]))
    end

    it "sees a modifier's body before its condition" do
      expect(locals("def m\n  a = 1 if a.nil?\nend\n", "a.nil?")).to(eq(%i[a]))
    end

    it "adds the locals a node binds when written after it", :aggregate_failures do
      expect(locals("def m\n  (v = 1) && 2\nend\n", "(v = 1) && 2")).to(eq([]))
      expect(locals("def m\n  (v = 1) && 2\nend\n", "(v = 1) && 2", after: true)).to(eq(%i[v]))
    end

    it "writes a call named like a bound local with parentheses" do
      expect(written("def m(d)\n  e\nend\n", "e") { read("d") }).to(eq("d()"))
    end
  end

  describe "text kept as written" do
    let(:source) do
      "def m(a)\n  call(a, # why\n       2)\n  a.map { |x|\n    x }\n  a ? f(1) : 'q'\n  f a, 1\n  return a if a\n  " \
        "x = %w[p q]\n  y = <<~T\n    t\n  T\n  defined? a\n  yield a\n  super a\nend\n"
    end

    it "keeps an untouched subtree's text, comments and line breaks included", :aggregate_failures do
      expect(written(source, "call(a, # why\n       2)") { |call| call.copy(name: :other) }).to(eq("other(a, 2)"))
      expect(written(source, "a.map { |x|\n    x }") { |call| call.copy(name: :each) }).to(eq("a.each { |x|\n    x }"))
      expect(written(source, "a ? f(1) : 'q'") { |ternary| listed(ternary) }).to(eq("[a ? f(1) : 'q']"))
    end

    it "writes afresh what reads differently elsewhere", :aggregate_failures do
      ["f a, 1", "return a if a", "defined? a", "yield a", "super a"].each do |slice|
        expect(written(source, slice) { |node| listed(node) }).not_to(include(slice))
      end
      expect(written(source, "%w[p q]") { |words| words.copy(elements: words.elements.reverse) }).to(eq('["q", "p"]'))
      expect(written(source, "y = <<~T") { |write| write.copy(name: :z) }).to(eq('z = "t\n"'))
    end

    it "writes statements on one line when joined" do
      root = tree(source)
      scribe = described_class.new(tree("a = 1\nb = a").statements).at(root, find(root, "a"))
      expect(scribe.joined.text).to(eq("a = 1; b = a"))
    end

    it "indents a written node to its line" do
      nested = "class A\n  def m\n    if a\n      1\n    end\n  end\nend\n"
      expect(written(nested, "if a\n      1\n    end") { |node| node.copy(predicate: read("b")) })
        .to(eq("if b\n      1\n    end"))
    end
  end

  describe "argument lists" do
    it "writes an emptied argument list beside a block argument as the block argument alone", :aggregate_failures do
      call = tree("foo(a, &b)").statements.body.first
      expect(described_class.new(call.copy(arguments: call.arguments.copy(arguments: []))).source).to(eq("foo(&b)"))
      forwarded = tree("super(a, &b)").statements.body.first
      emptied = forwarded.copy(arguments: forwarded.arguments.copy(arguments: []))
      expect(described_class.new(emptied).source).to(eq("super(&b)"))
    end
  end

  describe "regexp parts" do
    def part(source) = tree(source).statements.body.first

    it "writes a part as written until a rewrite changes its value", :aggregate_failures do
      regexp = part("/\\A\\/\#{x}_id\\z/")
      expect(described_class.new(regexp).source).to(eq("/\\A\\/\#{x}_id\\z/"))
      changed = regexp.copy(parts: [regexp.parts.first.copy(unescaped: "a/"), *regexp.parts.drop(1)])
      expect(described_class.new(changed).source).to(eq("/\#{\"a/\"}\#{x}_id\\z/"))
    end
  end

  describe Kimera::FactoryBlock do
    def block(source) = Kimera::Scribe.parse(source).statements.body.first.block

    {
      "A.new do\n  def x = 1\nend" => true, "A.new do |c|\n  def x = 1\nend" => false,
      "A.new do\n  x = 1\nend" => false, "A.new do\nend" => false, "A.new(&b)" => false
    }.each do |source, defining|
      it "reads `#{source.lines.first.chomp}` as #{"not " unless defining}a class body" do
        expect(described_class.new(block(source)).defining?).to(be(defining))
      end
    end

    it "reads no block as no class body" do
      expect(described_class.new(nil).defining?).to(be(false))
    end
  end
end
