# frozen_string_literal: true

require_relative "../../rewrite/ast_walk"
require_relative "../../rewrite/directive"

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
  NONE = {}.compare_by_identity.freeze

  def initialize(tree)
    @tree = tree
  end

  def drops?(point)
    node = nodes[[point.location.start_offset, point.location.finish, point.node_type.to_sym]]
    holder = node && holder(node)
    return false unless holder && taker?(holder)
    point.mutants.any? { |mutant| dropped?(holder, node, mutant.directive) }
  end

  private

  def nodes = @_nodes ||= index

  def index
    {}.tap { |found| Kimera::Rewrite::AstWalk.new(@tree).visit { |node| found[[*span(node), node.type]] ||= node } }
  end

  def span(node) = [node.location.start_offset, node.location.end_offset]

  def holder(node)
    from, to = span(node)
    held = nodes.values.select { |found| found.type == :def_node && !found.equal?(node) && within?(found, from, to) }
    held.max_by { |found| found.location.start_offset }
  end

  def within?(found, from, to)
    start, finish = span(found)
    start <= from && to <= finish
  end

  def taker?(holder) = !declared?(holder.parameters) && live(holder.body, NONE).positive?

  def declared?(parameters)
    parameters && (parameters.block || parameters.keyword_rest&.type == :forwarding_parameter_node)
  end

  def dropped?(holder, node, directive)
    live(holder.body, { node => Kimera::Rewrite::Directive.new(directive).apply(node) }.compare_by_identity).zero?
  rescue StandardError
    true
  end

  def live(node, swap)
    node = swap.fetch(node, node)
    return 0 if node.nil? || node.type == :def_node
    (use?(node) ? 1 : 0) + reached(node, swap).sum { |child| live(child, swap) }
  end

  def use?(node) = node.type == :yield_node || (SUPERS.include?(node.type) && node.block.nil?)

  def reached(node, swap)
    known = BRANCHES.include?(node.type) ? fixed(node.predicate, swap) : nil
    return node.compact_child_nodes if known.nil?
    [node.predicate, known ^ (node.type == :unless_node) ? node.statements : other(node)]
  end

  def other(node)
    node.compact_child_nodes.find { |child| !child.equal?(node.predicate) && !child.equal?(node.statements) }
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

  def last(body, swap) = fixed(body.type == :statements_node ? body.body.last : body, swap)

  def both(left, right) = [left, right].include?(false) ? false : left && right

  def either(left, right) = [left, right].include?(true) || ([left, right].include?(nil) ? nil : false)
end
