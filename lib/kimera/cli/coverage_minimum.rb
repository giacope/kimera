# frozen_string_literal: true

require "prism"

module Kimera
end

class Kimera::CLI
end

module Kimera::CLI::CoverageMinimum
  CALLS = %i[minimum_coverage minimum_coverage_by_file].freeze
  EXITS = %i[exit exit! abort].freeze
  JUMPS = %i[return_node next_node break_node].freeze
  CONSTANTS = %i[constant_read_node constant_path_node].freeze
  CONDITIONALS = %i[if_node unless_node case_node case_match_node].freeze
  SHORTCUTS = %i[and_node or_node].freeze

  module_function

  def ungated?(source)
    return false unless source.include?("minimum_coverage") && !source.include?("KIMERA")
    result = Prism.parse(source)
    result.failure? || floor?(result.value)
  end

  def floor?(node)
    return true if minimum?(node)
    tests = tests(node)
    return tests.any? { |test| floor?(test) } if guarded?(tests)
    return statements?(node.body) if node.is_a?(Prism::StatementsNode)
    node.compact_child_nodes.any? { |child| floor?(child) }
  end

  def statements?(body)
    body.each do |statement|
      return true if floor?(statement)
      return false if guarded?(tests(statement)) && exits?(statement)
    end
    false
  end

  def tests(node)
    type = node.type
    return [node.left] if SHORTCUTS.include?(type)
    return [] unless CONDITIONALS.include?(type)
    [node.predicate, *branches(node)].compact
  end

  def branches(node) = node.is_a?(Prism::CaseNode) ? node.conditions.flat_map(&:conditions) : []

  def minimum?(node) = node.is_a?(Prism::CallNode) && CALLS.include?(node.name)

  def guarded?(tests) = tests.any? { |test| env?(test) }

  def env?(node)
    return true if CONSTANTS.include?(node.type) && node.name == :ENV
    node.compact_child_nodes.any? { |child| env?(child) }
  end

  def exits?(node)
    return true if JUMPS.include?(node.type)
    return true if node.is_a?(Prism::CallNode) && EXITS.include?(node.name)
    node.compact_child_nodes.any? { |child| exits?(child) }
  end
end
