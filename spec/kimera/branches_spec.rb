# frozen_string_literal: true

require "kimera/parsing/branches"

RSpec.describe(Kimera::Branches) do
  def branches(source) = described_class.new(Prism.parse(source).value.statements.body.first)

  def sliced(source) = branches(source).bodies.map { |body| body.slice.strip }

  it "lists the body of every branch of an if, elsif and else chain, and of an unless and its else" do
    expect([sliced("if a\n  1\nelsif b\n  2\nelse\n  3\nend\n"), sliced("unless a\n  1\nelse\n  2\nend\n")])
      .to(eq([%w[1 2 3], %w[1 2]]))
  end

  it "finds nothing after a branch with no else" do
    expect([branches("if a\n  1\nend\n").following, branches("unless a\n  1\nend\n").following]).to(eq([nil, nil]))
  end

  # Prism 1.2 renamed consequent to subsequent (if) and else_clause (unless);
  # the old name still answers, with a deprecation warning.
  it "reads the clause after a branch without Prism's deprecated name" do
    deprecated = Warning[:deprecated]
    Warning[:deprecated] = true
    expect { %w[unless if].each { |word| branches("#{word} a\n  1\nelse\n  2\nend\n").following } }
      .not_to(output.to_stderr)
  ensure
    Warning[:deprecated] = deprecated
  end

  it "reads consequent on a Prism that predates the rename" do
    expect(described_class.new(Struct.new(:statements, :consequent).new(:body, :rest)).following).to(eq(:rest))
  end
end
