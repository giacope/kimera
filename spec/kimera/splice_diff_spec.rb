# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/synthesis/overlay"

# The parts of a splice: where a rewrite changed a tree, what a source's
# tree holds, and what the spliced text is for each shape of point.
RSpec.describe(Kimera::SpliceDiff) do
  def read(source) = Kimera::Scribe.parse(source).statements.body.first

  def path(node, mutated) = described_class.new(node, mutated).path.map { |pair| pair.map(&:slice) }

  it "stops where a node's own field changed" do
    node = read("a > b")
    expect(described_class.new(node, node.copy(name: :>=)).path.size).to(eq(1))
  end

  it "descends through the one child a rewrite changed", :aggregate_failures do
    node = read("if a then 1 end")
    expect(path(node, node.copy(predicate: read("true"))).last).to(eq(%w[a true]))
    list = read("[a, b, c]")
    expect(path(list, list.copy(elements: [list.elements[0], read("x"), list.elements[2]])).last).to(eq(%w[b x]))
  end

  it "stops at a change of type, of a list's size, or of a value", :aggregate_failures do
    expect(described_class.new(read("a && b"), read("a || b")).path.size).to(eq(1))
    list = read("[a, b]")
    expect(described_class.new(list, list.copy(elements: [list.elements[0]])).path.size).to(eq(1))
    expect(described_class.new(read("'q'"), read("'q'").copy(unescaped: "")).path.size).to(eq(1))
  end

  # Two kinds of node that hold the same one changed child: the change is the
  # kind, not the child.
  it "stops at a change of type even when only a child differs" do
    held = { a: Struct.new(:child) { def type = :a_node }, b: Struct.new(:child) { def type = :b_node } }
    expect(described_class.new(held[:a].new(read("x")), held[:b].new(read("y"))).path.size).to(eq(1))
  end

  it "never replaces a self receiver alone", :aggregate_failures do
    call = read("self.class.new")
    expect(described_class.new(call, call.copy(receiver: call.receiver.receiver)).path.size).to(eq(1))
    other = read("x.class.new")
    expect(described_class.new(other, other.copy(receiver: other.receiver.receiver)).path.size).to(eq(2))
  end

  describe Kimera::SpliceIndex do
    let(:root) { Kimera::Scribe.parse("a(<<~T, 'b')\n  t\nT\nc('d')\n") }
    let(:index) { described_class.new(root) }

    def find(slice)
      root.statements.body.flat_map { |node| [node, *node.arguments.arguments] }.find { |n| n.slice == slice }
    end

    it "knows the lines a heredoc opens on", :aggregate_failures do
      expect([index.heredoc?(find("'b'")), index.heredoc?(find("'d'"))]).to(eq([true, false]))
      expect(index.parent(find("'d'")).type).to(eq(:arguments_node))
    end
  end

  describe Kimera::SourceMap do
    {
      ["x = 1\n__END__\nd\n", "y"] => "y\n__END__\nd\n", ["x = 1\n__END__\nd\n", "y\n"] => "y\n__END__\nd\n",
      ["x = 1\n__END__\nd\n", ""] => "__END__\nd\n", ["# c\n# frozen-string-literal: true\nx\n", "y\n"] =>
        "# c\n# frozen-string-literal: true\ny\n", ["# only\n__END__\nd\n", ""] => "# only\n__END__\nd\n",
      ["# only\n# two\n", ""] => "# only\n# two\n", ["# é\nx = 1 # a\n", "y\n"] => "# é\ny\n"
    }.each do |(source, text), restored|
      it "restores #{text.inspect} written for #{source.inspect} as #{restored.inspect}" do
        expect(described_class.new(source).restore(text)).to(eq(restored))
      end
    end
  end

  describe Kimera::Scribe::Place do
    def locals(source, slice)
      root = Kimera::Scribe.parse(source)
      node = nil
      visit =
        proc { |each|
          node ||= each if each.slice == slice && each.type != :statements_node
          each.compact_child_nodes.each(&visit)
        }
      visit.call(root)
      described_class.of(root, node || read(slice)).locals.to_a.sort
    end

    it "binds a write's name after it, not at it, and an embedded part's binding just before", :aggregate_failures do
      expect(locals("def m\n  y = 2\nend\n", "y = 2")).to(eq([]))
      expect(locals("\"\#{a = 1}\#{a}\"", "\#{a}")).to(eq(%i[a]))
      expect(locals("x = 1\n", "zzzzzzzzzzzzzz")).to(eq([]))
    end

    it "keeps as written only what reads the same anywhere", :aggregate_failures do
      root = Kimera::Scribe.parse("def m(a)\n  [a .b, f(a,  1), a  +  b, yield(a,  1)]\nend\n")
      list = root.statements.body.first.body.body.first
      kept = described_class.of(root, list).slices.values
      expect(kept).to(include("a .b", "f(a,  1)", "a  +  b", "yield(a,  1)"))
    end
  end
end
