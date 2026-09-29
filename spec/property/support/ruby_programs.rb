# frozen_string_literal: true

require "pbt"

# Random Ruby methods for property specs: pure, loop-free expressions over the
# parameters, built to reach every operator family. A program is a tree of
# [template, *children]; "%1".."%3" in a template stand for its children, so
# shrinking can swap any node for one of its children or a bare parameter.
# A program is [signature, *statements]. Signatures vary the optional
# parameters (a second optional, a splat after them) and their defaults,
# some of which read `a` and can raise, so removing a default is tested for
# argument binding and for the order defaults are evaluated in.
#
# One shape stays out, as its source text can't round-trip: a bare range in
# a condition (`!(a...b)` reads back as a flip-flop). A range is always the
# receiver of two chained calls, so no one mutation leaves it bare.
# `(-%1)` over `-1` roots a call chain at a literal a mutation can unsign
# (`(--1.to_s)`), or leaves a literal the parser folds (`(--1)`).
# `([%1]...[%2]).to_s.size` has array literals for endpoints and prints the
# range instead of iterating.
class RubyPrograms < Pbt::Arbitrary::Arbitrary
  # Each hole is filled from DEFAULTS, or from LITERALS where `a` is itself
  # optional (its default can't read it).
  SIGNATURES = {
    "def m(a, b = %1, c: %2)" => %i[any any],
    "def m(a = %1, b = %2, c: %3)" => %i[literal any any],
    "def m(a, b = %1, d = %2, c: %3)" => %i[any any any],
    "def m(a = %1, b = %2, d = %3, c: %4)" => %i[literal any any any],
    "def m(a, b = %1, d = %2, *r, c: %3)" => %i[any any any]
  }.freeze
  SIMPLEST = ["def m(a, b = %1, c: %2)", ["2"], ["2"]].freeze
  DEFAULTS = { literal: %w[1 2 nil], any: ["2", "3", "nil", '"s"', "(1 / a)", "a.to_s", "(a + 1)"] }.freeze
  LEAVES = ["a", "b", "c", "0", "1", "2", "-1", "7", "nil", "true", "false", '"s"', ":k", "[]", "{}"].freeze
  UNARY = [
    "(!%1)", "(-%1)", "%1.to_s", "%1.to_s.size", "%1.abs", "%1&.succ", "%1.to_s.upcase", "Integer(%1)",
    "String(%1)", "%1.to_s.to_sym", "[%1].first", '"x#{%1}y"', "%1.to_s.match?(/1/)", "%1.nil?",
    "%1.to_s.to_i", "%1.respond_to?(:abs)", "Array(%1)", "(a...b).to_a.include?(%1)", "%1.to_s.split(\"\").first"
  ].freeze
  BINARY = [
    "(%1 + %2)", "(%1 - %2)", "(%1 * %2)", "(%1 / %2)", "(%1 % %2)", "(%1 == %2)", "(%1 != %2)",
    "(%1 < %2)", "(%1 <= %2)", "(%1 > %2)", "(%1 >= %2)", "(%1 && %2)", "(%1 || %2)", "(%1 & %2)",
    "(%1 | %2)", "(%1 <=> %2)", "[%1, %2]", "[%1, %2].max", "{ k: %1, j: %2 }.fetch(:k)", "{ k: %1 }[:k]",
    "[%1, %2].map { |x| x.to_s }", "[%1, %2].select { |x| x }",
    "[%1, %2].first(1)", "[%1, %2].include?(1)", "%1.eql?(%2)", "[%1, %2].sum(0)", "[%1, %2][1]",
    "%1.to_s.center(4, %2.to_s)", "([%1]...[%2]).to_s.size"
  ].freeze
  TERNARY = [
    "(%1 ? %2 : %3)", "(if %1 then %2 else %3 end)", "(unless %1 then %2 else %3 end)",
    "%1.clamp(%2, %3)", "[%1, %2, %3].compact.size", "%1.between?(%2, %3)"
  ].freeze
  STATEMENTS = ["%1", "a += %1", "return %1 if %2", "b = %1", "x = %1"].freeze
  FORMS = [LEAVES, UNARY, BINARY, TERNARY].freeze
  HOLE = /%(\d)/

  def initialize(depth: 3, statements: 3)
    super()
    @depth = depth
    @statements = statements
  end

  def generate(random = Random.new)
    [signature(random), *Array.new(random.rand(1..@statements)) { statement(random) }]
  end

  def shrink(current)
    signature, *body = current
    Enumerator.new do |out|
      simpler(signature).each { |s| out << [s, *body] }
      body.each_index { |i| out << [signature, *body[0...i], *body[(i + 1)..]] if body.size > 1 }
      body.each_with_index { |node, i| smaller(node).each { |s| out << [signature, *body.dup.tap { |c| c[i] = s }] } }
    end
  end

  def self.render(program)
    signature, *body = program
    "#{source(signature)}\n#{body.map { |statement| "  #{source(statement)}\n" }.join}end\n"
  end

  def self.source(node)
    template, *children = node
    template.gsub(HOLE) { source(children[Integer(::Regexp.last_match(1)) - 1]) }
  end

  private

  def signature(random)
    template, kinds = SIGNATURES.to_a.sample(random: random)
    [template, *kinds.map { |kind| [DEFAULTS.fetch(kind).sample(random: random)] }]
  end

  # The plainest signature first, then each default back to "2". Each step
  # leaves the plainest template or turns one more default into "2", so
  # shrinking can't cycle.
  def simpler(signature)
    template, *defaults = signature
    [(SIMPLEST unless signature == SIMPLEST), *plainer(template, defaults)].compact
  end

  def plainer(template, defaults)
    defaults.each_index.filter_map do |i|
      [template, *defaults.dup.tap { |d| d[i] = ["2"] }] unless defaults[i] == ["2"]
    end
  end

  def statement(random)
    template = STATEMENTS.sample(random: random)
    [template, *Array.new(holes(template)) { expression(random, @depth) }]
  end

  def expression(random, depth)
    arity = depth.zero? ? 0 : random.rand(0..3)
    [FORMS[arity].sample(random: random), *Array.new(arity) { expression(random, depth - 1) }]
  end

  def holes(template) = template.scan(HOLE).flatten.uniq.size

  # A node shrinks to a bare parameter, to one of its own subexpressions, or
  # by shrinking one child in place.
  def smaller(node)
    template, *children = node
    return [] if children.empty? && template == "a"
    Enumerator.new do |out|
      out << ["a"]
      children.each { |child| out << child }
      children.each_with_index do |child, i|
        smaller(child).each { |s| out << [template, *children.dup.tap { |c| c[i] = s }] }
      end
    end
  end
end
