# frozen_string_literal: true

require_relative "../support/unparse"
require_relative "../rewrite/ast_walk"
require_relative "../rewrite/directive"
require_relative "guardrail_dispatch"
require_relative "guardrail_interpolation"
require_relative "guardrail_factories"
require_relative "source_map"

class Kimera::Guardrail
  include Kimera::GuardrailDispatch
  include Kimera::GuardrailInterpolation
  include Kimera::GuardrailFactories

  attr_reader :applied

  Patch =
    Data.define(:map, :span, :directive) do
      def apply(rebuilt, original)
        expression = original.location&.expression
        return rebuilt unless expression && map.span(expression) == span
        Kimera::Rewrite::Directive.apply(rebuilt, directive)
      end
    end

  def initialize(map, points)
    @map = map
    @points = points
    @applied = []
  end

  def tree
    transform(@map.ast)
  end

  def rewrite(node)
    [Kimera::Unparse.unparse(transform(node)), applied]
  end

  def transform(node) = weave(node).first

  def bake(location, directive)
    target = [location.start_offset, location.finish]
    prune(overlay(target, directive)) if spans.include?(target)
  end

  private

  def spans
    Set.new.tap { |found| Kimera::Rewrite::AstWalk.visit(@map.ast) { |node| found << span(node) } }
  end

  def span(node)
    expression = node.location&.expression
    expression && @map.span(expression)
  end

  def weave(node)
    return [node, node] unless node.is_a?(Parser::AST::Node)
    woven = node.children.map { |child| weave(child) }
    bare = settle(node.updated(nil, woven.map(&:last)))
    [reopen(dispatch(settle(node.updated(nil, woven.map(&:first))), bare, points(node))), reopen(bare)]
  end

  def settle(node) = node.type == :dstr ? flatten(node) : node

  def overlay(target, directive)
    patch = Patch.new(@map, target, directive)
    Kimera::Rewrite::AstWalk.rebuild(@map.ast) do |rebuilt, original|
      reopen(patch.apply(rebuilt, original))
    end
  end

  def points(node)
    expr = node.location&.expression
    return [] unless expr
    ranges.fetch(@map.span(expr), [])
  end

  def ranges
    @_ranges ||= group(@points)
  end

  def ast(type, *children)
    Parser::AST::Node.new(type, children)
  end
end
