# frozen_string_literal: true

require "kimera/rewrite/ast_walk"
require "kimera/scribe"

RSpec.describe(Kimera::Rewrite::AstWalk) do
  let(:tree) { Kimera::Scribe.parse("f(a, [b, c]) { d }") }

  # A rebuild that changes nothing hands back the very tree, so nothing is copied.
  it "keeps every node a rebuild leaves as it was" do
    expect(described_class.new(tree).rebuild { |node| node }).to(be(tree))
  end

  def renamed(node) = node.type == :call_node && node.name == :c ? node.copy(name: :e) : node

  it "copies only the nodes above the one it changes", :aggregate_failures do
    rebuilt = described_class.new(tree).rebuild { |node| renamed(node) }
    call = rebuilt.statements.body.first
    expect(Kimera::Scribe.new(rebuilt).source).to(eq("f(a, [b, e]) {\n  d\n}"))
    expect(call.block).to(be(tree.statements.body.first.block))
  end
end
