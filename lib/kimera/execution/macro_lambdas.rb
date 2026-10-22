# frozen_string_literal: true

require "prism"
require_relative "../registry/mutation_point"
require_relative "../parsing/document"

module Kimera
  module Execution
  end
end

class Kimera::Execution::MacroLambdas
  REASON = Kimera::MutationPoint::MACRO_REASON

  def initialize(registry, root)
    @registry = registry
    @given = root
  end

  def quarantine!(coverage)
    @registry.files.each do |file|
      ranges = handed(file)
      @registry.at(file).each { |point| point.unsafe!(REASON) if shadowed?(point, ranges, coverage) }
    end
  end

  private

  def root = @_root ||= File.expand_path(@given)

  def shadowed?(point, ranges, coverage)
    point.safe? && !point.revisit && point.inside?(ranges) && point.uncovered?(coverage)
  end

  def handed(file) = lambdas(Kimera::Syntax::Document.new(root, file).result.value, argument: false)

  def lambdas(node, argument:)
    return [] if node.is_a?(Prism::DefNode)
    return [node.location] if argument && node.is_a?(Prism::LambdaNode)
    node.compact_child_nodes.flat_map { |child| lambdas(child, argument: argument || passed?(node, child)) }
  end

  def passed?(node, child) = node.is_a?(Prism::CallNode) && child.equal?(node.arguments)
end
