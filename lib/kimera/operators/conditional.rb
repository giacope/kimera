# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::Conditional < Kimera::Operators::Base
  LITERAL_CONDITIONS = { "true" => TrueNode, "false" => FalseNode }.freeze

  class << self
    def key = "conditional"
  end

  def variants(node, **)
    return unless conditional?(node)
    return if elsif?(node)
    return if memoized?(node)
    LITERAL_CONDITIONS.filter_map { |to, literal| flip(to) unless node.predicate.is_a?(literal) }
  end

  private

  def flip(to)
    Kimera::Operators::Variant.new(label: "condition => #{to}", directive: directive("condition", to: to))
  end

  def conditional?(node)
    node.is_a?(IfNode) || node.is_a?(UnlessNode)
  end

  def elsif?(node)
    node.is_a?(IfNode) && node.if_keyword_loc&.slice == "elsif"
  end

  def memoized?(node)
    predicate = node.predicate
    predicate.is_a?(DefinedNode) &&
      predicate.value.is_a?(InstanceVariableReadNode)
  end
end
