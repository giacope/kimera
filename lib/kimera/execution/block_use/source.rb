# frozen_string_literal: true

require_relative "../../rewrite/fit"

module Kimera
  module Execution
  end
end

class Kimera::Execution::BlockUse; end

class Kimera::Execution::BlockUse::Source
  FALSY = %i[false_node nil_node].freeze
  TRUTHY = %i[
    true_node integer_node float_node rational_node imaginary_node string_node symbol_node lambda_node source_line_node
  ].freeze
  SUPERS = %i[super_node forwarding_super_node].freeze
  BRANCHES = %i[if_node unless_node].freeze
  LOOKED = %i[call_node array_node parentheses_node].freeze
  NONE = {}.compare_by_identity.freeze

  def initialize(tree)
    @tree = tree
  end

  def drops?(point)
    node, holder = point.anchored(nodes) { return false }
    return false unless holder && taker?(holder)
    point.each.any? { |mutant| dropped?(holder, node, mutant.rewrite(Kimera::Rewrite::Directive)) }
  end

  private

  def nodes = @_nodes ||= entries(@tree, nil).to_h

  def entries(node, holder)
    inner = node.type == :def_node ? node : holder
    place = [node.location.start_offset, node.location.end_offset, node.type.to_s]
    [[place, [node, holder]], *node.compact_child_nodes.flat_map { |child| entries(child, inner) }]
  end

  def taker?(holder) = !declared?(holder.parameters) && live(holder.body, NONE).positive?

  def declared?(parameters)
    parameters && (parameters.block || parameters.keyword_rest&.type == :forwarding_parameter_node)
  end

  def dropped?(holder, node, directive)
    applied = Kimera::Rewrite::Fit.new(directive).applied(node) { return true }
    live(holder.body, { node => applied }.compare_by_identity).zero?
  end

  def live(node, swap)
    node = swap.fetch(node, node)
    return 0 if node.nil? || node.type == :def_node
    return checked(node.value, swap) if node.type == :defined_node
    (use?(node) ? 1 : 0) + reached(node, swap).sum { |child| live(child, swap) }
  end

  def checked(node, swap)
    node = swap.fetch(node, node)
    return node.type == :yield_node ? 1 : 0 unless LOOKED.include?(node.type)
    evaluated(node, swap) + looked(node).sum { |each| checked(each, swap) }
  end

  def evaluated(node, swap) = node.type == :call_node ? live(node.receiver, swap) : 0

  def looked(node)
    case node.type
    when :call_node then [*node.arguments&.arguments]
    when :array_node then node.elements
    else node.body&.body&.one? ? node.body.body : []
    end
  end

  def use?(node) = node.type == :yield_node || (SUPERS.include?(node.type) && node.block.nil?)

  def reached(node, swap)
    known = BRANCHES.include?(node.type) ? fixed(node.predicate, swap) : nil
    return node.compact_child_nodes if known.nil?
    [node.predicate, *(known ^ (node.type == :unless_node) ? [node.statements] : others(node))]
  end

  def others(node)
    node.compact_child_nodes.select { |child| !child.equal?(node.predicate) && !child.equal?(node.statements) }.first(1)
  end

  def fixed(node, swap)
    node = swap.fetch(node, node)
    case node.type
    when *FALSY then false
    when *TRUTHY then true
    when :parentheses_node then last(node.body, swap)
    when :and_node then both(fixed(node.left, swap), fixed(node.right, swap))
    when :or_node then either(fixed(node.left, swap), fixed(node.right, swap))
    end
  end

  def last(body, swap) = body && fixed(body.body.last, swap)

  def both(left, right) = [left, right].include?(false) ? false : left && right

  def either(left, right) = [left, right].include?(true) || ([left, right].include?(nil) ? nil : false)
end
