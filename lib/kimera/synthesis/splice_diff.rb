# frozen_string_literal: true

require_relative "../parsing/syntax"

class Kimera::SpliceDiff
  def initialize(original, mutated)
    @original = original
    @mutated = mutated
  end

  def path
    found = [[@original, @mutated]]
    while (pair = differing(*found.last))
      found << pair
    end
    found
  end

  private

  def differing(original, mutated)
    return unless alike?(original, mutated)
    pairs = fields(original).zip(fields(mutated)).reject { |left, right| left == right }
    pair = pairs.first if pairs.one? && pairs.first.all?(Kimera::Syntax::Node)
    pair unless pair && receiving?(original, pair)
  end

  def alike?(original, mutated) = original.type == mutated&.type

  def receiving?(node, pair)
    node.type == :call_node && pair.first.equal?(node.receiver) && pair.any? { |each| each.type == :self_node }
  end

  def fields(node)
    values = node.deconstruct_keys(nil).except(:location, :node_id).values
    values.flat_map { |value| value.is_a?(Array) ? [value.size, *value] : [value] }
  end
end
