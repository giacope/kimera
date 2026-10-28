# frozen_string_literal: true

require "kimera/synthesis/outline"

# Two trees of one Outline are one program however their source spelled it:
# the warm overlay's rewrite of a method, read back, against the method it
# rewrote (Kimera::Unwoven).
RSpec.describe(Kimera::Outline) do
  def tree(source) = Kimera::Syntax.parse(source).value

  def outline(node) = described_class.new(node).shape

  # The hash a guard over its key leaves: the parser flagged it as having an
  # expression key, the original as having only symbol keys.
  def unguarded(source)
    Kimera::Rewrite::AstWalk.new(tree(source)).rebuild do |node|
      node.type == :if_node ? node.subsequent.statements.body.first : node
    end
  end

  {
    "a lone expression in parentheses" => ["(a)", "a"], "a lone statement list" => ["begin; a; end", "begin\na\nend"],
    "a string split into parts" => ['"a" "b"', '"ab"'], "a literal interpolated" => ["\"\#{\"a\"}b\"", '"ab"'],
    "a heredoc" => ["<<~X\n  a\n  b\nX", '"a\nb\n"'], "an escaped character" => ['"\u{e9}"', '"é"'],
    "a symbol escaped" => [':"\u{e9}"', ":é"], "a hexadecimal integer" => %w[0x1F 31],
    "a binary integer" => %w[0b1 1], "an octal integer" => %w[0o7 7],
    "strings beside an interpolation" => ["\"a\" \"b\#{c}\"", "\"ab\#{c}\""]
  }.each do |kind, (one, other)|
    it "reads #{kind} as the same program" do
      expect(outline(tree(one))).to(eq(outline(tree(other))))
    end
  end

  it "reads a key a guard held as the key" do
    expect(outline(unguarded("f(if c then :a else :b end => 1)"))).to(eq(outline(tree("f(:b => 1)"))))
  end

  {
    "another string" => ['"a"', '"b"'], "a call interpolated" => ["\"\#{a}\"", '"a"'], "another integer" => %w[0x1F 30],
    "a string in another encoding" => ["# encoding: binary\n\"\\u{3042}\"", "# encoding: binary\n\"\\xE3\\x81\\x82\""],
    "a safe call" => %w[a&.b a.b], "an exclusive range" => %w[a...b a..b], "another statement" => ["a; b", "a; c"],
    "another interpolation" => ["\"a\#{b}c\"", "\"a\#{d}c\""], "other text beside it" => ["\"a\#{b}c\"", "\"a\#{b}d\""]
  }.each do |kind, (one, other)|
    it "tells #{kind} apart" do
      expect(outline(tree(one))).not_to(eq(outline(tree(other))))
    end
  end
end
