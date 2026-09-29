# frozen_string_literal: true

require "pbt"

# Random Ruby methods for property specs: pure, loop-free expressions over the
# parameters, built to reach every operator family. A program is a tree of
# [template, *children]; "%1".."%3" in a template stand for its children, so
# shrinking can swap any node for one of its children or a bare parameter.
#
# Three shapes stay out, as their source text can't round-trip: an array
# literal as a range endpoint (unparser raises), unary minus on a call chain
# rooted at a numeric literal (`-(0.to_s)` prints as `-0.to_s`), and a bare
# range in a condition (`!(a...b)` reads back as a flip-flop). Hence
# `(a...b).to_a` and `-(%1)`.
class RubyPrograms < Pbt::Arbitrary::Arbitrary
  SIGNATURE = "def m(a, b = 2, c: 3)"
  LEAVES = ["a", "b", "c", "0", "1", "2", "-1", "7", "nil", "true", "false", '"s"', ":k", "[]", "{}"].freeze
  UNARY = [
    "(!%1)", "-(%1)", "%1.to_s", "%1.to_s.size", "%1.abs", "%1&.succ", "%1.to_s.upcase", "Integer(%1)",
    "String(%1)", "%1.to_s.to_sym", "[%1].first", '"x#{%1}y"', "%1.to_s.match?(/1/)", "%1.nil?",
    "%1.to_s.to_i", "%1.respond_to?(:abs)", "Array(%1)", "(a...b).to_a.include?(%1)", "%1.to_s.split(\"\").first"
  ].freeze
  BINARY = [
    "(%1 + %2)", "(%1 - %2)", "(%1 * %2)", "(%1 / %2)", "(%1 % %2)", "(%1 == %2)", "(%1 != %2)",
    "(%1 < %2)", "(%1 <= %2)", "(%1 > %2)", "(%1 >= %2)", "(%1 && %2)", "(%1 || %2)", "(%1 & %2)",
    "(%1 | %2)", "(%1 <=> %2)", "[%1, %2]", "[%1, %2].max", "{ k: %1, j: %2 }.fetch(:k)", "{ k: %1 }[:k]",
    "[%1, %2].map { |x| x.to_s }", "[%1, %2].select { |x| x }",
    "[%1, %2].first(1)", "[%1, %2].include?(1)", "%1.eql?(%2)", "[%1, %2].sum(0)", "[%1, %2][1]",
    "%1.to_s.center(4, %2.to_s)"
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
    Array.new(random.rand(1..@statements)) { statement(random) }
  end

  def shrink(current)
    Enumerator.new do |out|
      current.each_index { |i| out << (current[0...i] + current[(i + 1)..]) if current.size > 1 }
      current.each_with_index { |node, i| smaller(node).each { |s| out << current.dup.tap { |c| c[i] = s } } }
    end
  end

  def self.render(program)
    body = program.map { |statement| "  #{source(statement)}\n" }.join
    "#{SIGNATURE}\n#{body}end\n"
  end

  def self.source(node)
    template, *children = node
    template.gsub(HOLE) { source(children[Integer(::Regexp.last_match(1)) - 1]) }
  end

  private

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
