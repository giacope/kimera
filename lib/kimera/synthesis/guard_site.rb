# frozen_string_literal: true

require_relative "splice_diff"

class Kimera::GuardSite
  STOPS = %i[statements_node def_node class_node module_node singleton_class_node block_node lambda_node].freeze
  OPENED = %i[string_node symbol_node x_string_node interpolated_string_node interpolated_symbol_node array_node].freeze
  ENCLOSING = %i[defined_node match_write_node alias_method_node alias_global_variable_node undef_node].freeze
  NESTED = %w[_target_node _parameter_node _pattern_node].freeze

  def initialize(index)
    @index = index
  end

  def of(node, mutated)
    path = Kimera::SpliceDiff.new(node, mutated).path
    lifted(*(path.reverse.find { |each, _| site?(each) } || path.first))
  end

  private

  def lifted(node, mutated)
    until site?(node)
      parent = @index.parent(node)
      return if STOPS.include?(parent.type)
      mutated = parent.copy(**replaced(parent, node, mutated))
      node = parent
    end
    [node, mutated]
  end

  def replaced(parent, child, mutated)
    fields = parent.deconstruct_keys(nil).select { |_, value| holds?(value, child) }
    fields.transform_values { |value| value.is_a?(Array) ? swapped(value, child, mutated) : mutated }
  end

  def holds?(value, child) = value.equal?(child) || (value.is_a?(Array) && value.any? { |item| item.equal?(child) })

  def swapped(items, child, mutated) = items.map { |item| item.equal?(child) ? mutated : item }

  def site?(node)
    type = node.type
    return false if Kimera::SpliceDiff::HELD.include?(type) || type.end_with?(*NESTED)
    return false if OPENED.include?(type) && !opened?(node)
    parent = @index.parent(node)
    !ENCLOSING.include?(parent.type) && !parent.type.start_with?("interpolated_") && !captured?(node, parent)
  end

  def opened?(node)
    (node.opening_loc && !label?(node)) || (node.type == :interpolated_string_node && node.parts.all? { opened?(it) })
  end

  def label?(node) = node.closing_loc&.slice&.end_with?(":")

  def captured?(node, parent)
    parent.type == :call_node && @index.parent(parent).type == :match_write_node && node.equal?(parent.receiver)
  end
end
