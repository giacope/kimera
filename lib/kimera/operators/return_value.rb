# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::ReturnValue < Kimera::Operators::Base
  def key = "return_value"

  SKIPPED = [NilNode, ParenthesesNode].freeze
  POSITIONS = Hash.new(->(_operator, _node) {}).merge(tail: ->(operator, node) { operator.tail(node) }).freeze

  def variants(node, position:)
    return returned(node) if node.is_a?(ReturnNode)
    POSITIONS[position].call(self, node)
  end

  private

  def tail(node)
    solo("tail => nil", Kimera::Operators::STATEMENT_DELETION) if nilable?(node)
  end

  public :tail

  def nilable?(node)
    return false if identifier?(node)
    SKIPPED.none? { |kind| node.is_a?(kind) }
  end

  def returned(node)
    args = arguments(node)
    return if args.empty? || (args in [NilNode])
    solo("return => return nil", "return_nil")
  end
end
