# frozen_string_literal: true

require_relative "../scribe"
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

  Patch =
    Data.define(:map, :span, :directive) do
      def apply(rebuilt, original)
        expression = original.location&.expression
        return rebuilt unless expression && map.span(expression) == span
        Kimera::Rewrite::Directive.new(directive).apply(rebuilt)
      end
    end

  def initialize(map, points)
    @map = map
    @points = points
  end

  def tree = @_tree ||= transform(@map.ast)

  def applied = activated(tree)

  def rewrite(node)
    woven = transform(node)
    [Kimera::Scribe.new(woven).source, activated(woven)]
  end

  def activated(node)
    return [] unless node.is_a?(Parser::AST::Node)
    children = node.children
    own = children.first(2) == [runtime, :active?] ? [children[2].children.first] : []
    own + children.flat_map { |child| activated(child) }
  end

  def transform(node) = weave(node).first

  def bake(location, directive)
    target = [location.start_offset, location.finish]
    prune(overlay(target, directive)) if spans.include?(target)
  end

  private

  def spans
    Set.new.tap { |found| Kimera::Rewrite::AstWalk.new(@map.ast).visit { |node| found << span(node) } }
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
    Kimera::Rewrite::AstWalk.new(@map.ast).rebuild do |rebuilt, original|
      reopen(patch.apply(rebuilt, original))
    end
  end

  def points(node)
    expression = node.location&.expression
    return [] unless expression
    (@_ranges ||= group(@points)).fetch(@map.span(expression), [])
  end

  def ast(type, *children)
    Parser::AST::Node.new(type, children)
  end
end
