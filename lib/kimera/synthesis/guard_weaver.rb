# frozen_string_literal: true

require_relative "../support/unparse"
require_relative "../rewrite/ast_walk"
require_relative "../rewrite/directive"
require_relative "guardrail_dispatch"
require_relative "guardrail_interpolation"
require_relative "guardrail_value_objects"
require_relative "source_map"

class Kimera::Guardrail
  include Kimera::GuardrailDispatch
  include Kimera::GuardrailInterpolation
  include Kimera::GuardrailValueObjects

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

  def transform(node)
    Kimera::Rewrite::AstWalk.rebuild(node) { |rebuilt, original| rebuild(rebuilt, original) }
  end

  def bake(location, directive)
    prune(overlay([location.start_offset, location.finish], directive))
  end

  private

  def rebuild(rebuilt, original)
    rebuilt = flatten(rebuilt) if rebuilt.type == :dstr
    rebuilt = dispatch(rebuilt, points(original))
    reopen(rebuilt)
  end

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
