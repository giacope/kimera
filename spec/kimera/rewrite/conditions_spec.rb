# frozen_string_literal: true

require "prism"
require "kimera/rewrite/conditions"
require "kimera/support/unparse"

RSpec.describe(Kimera::Rewrite::Conditions) do
  let(:forms) do
    [
      "if r then 1 end", "1 if r", "unless r then 1 end", "1 unless r", "if x then 1 elsif r then 2 end",
      "while r do end", "until r do end", "begin; end while r", "begin; end until r", "r ? 1 : 2", "!r", "not r",
      "r.!", "!!r", "if x && r then 1 end", "if r || x then 1 end", "x and r ? 1 : 2", "!(x or r)",
      "if ((r)) then 1 end", "if begin; r; end then 1 end", "x && r", "if (x; r) then 1 end", "if (y = r) then 1 end",
      "if (x ? r : 1) then 1 end", "if (if x then r end) then 1 end", "if r.itself then 1 end", "f(!x, r)",
      "case when r then 1 end", "[1].select { r }"
    ]
  end

  literals = { "range" => "(1...2)", "regexp" => "/r/" }.freeze

  # `r` stands for the literal a mutation leaves: parsed in place, the parser
  # would already read it as a condition.
  def placed(form, literal)
    swap(Kimera::Unparse.parse(form), Kimera::Unparse.parse(literal))
  end

  def swap(node, literal)
    return node unless node.is_a?(Parser::AST::Node)
    return literal if node == Parser::AST::Node.new(:send, [nil, :r])
    node.updated(nil, node.children.map { swap(it, literal) })
  end

  # What Ruby runs when the tree is written out.
  def rereads?(tree)
    Prism.parse(Kimera::Unparse.unparse(tree)).value.inspect.match?(/FlipFlopNode|MatchLastLineNode/)
  end

  literals.each do |kind, literal|
    it "flags a #{kind} literal exactly where Ruby reads it back as a condition", :aggregate_failures do
      forms.each do |form|
        tree = placed(form, literal)
        expect(described_class.misread?(tree, tested: false)).to(eq(rereads?(tree)), form)
      end
    end
  end

  it "flags a literal in a tree that is itself tested", :aggregate_failures do
    expect(described_class.misread?(Kimera::Unparse.parse("(1...2)"), tested: true)).to(be(true))
    expect(described_class.misread?(Kimera::Unparse.parse("x || /r/"), tested: true)).to(be(true))
    expect(described_class.misread?(Kimera::Unparse.parse("(1...2).to_a"), tested: true)).to(be(false))
    expect(described_class.misread?(Kimera::Unparse.parse("(1...2)"), tested: false)).to(be(false))
  end

  it "leaves what the source already tests alone" do
    expect(described_class.misread?(Kimera::Unparse.parse("if (a..b) && /r/ then 1 end"), tested: false)).to(be(false))
  end

  it "finds the nodes where Ruby tests a condition" do
    tree = Kimera::Unparse.parse("if x && y.z then 1 end")
    tested = described_class.places(tree).filter_map { |node, test| Kimera::Unparse.unparse(node) if test }
    expect(tested).to(eq(["x && y.z", "x", "y.z"]))
  end
end
