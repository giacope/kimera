# frozen_string_literal: true

require_relative "../parsing/syntax"

class Kimera::SpliceDiff
  HELD = %i[
    statements_node arguments_node parameters_node block_parameters_node block_node embedded_statements_node
    embedded_variable_node else_node when_node in_node rescue_node ensure_node implicit_node implicit_rest_node
    keyword_hash_node multi_target_node begin_node def_node flip_flop_node match_last_line_node
    interpolated_match_last_line_node block_argument_node assoc_node assoc_splat_node splat_node
    class_node module_node singleton_class_node program_node
  ].freeze

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
