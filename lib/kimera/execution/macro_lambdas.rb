# frozen_string_literal: true

require "prism"
require_relative "../registry/mutation_point"
require_relative "../parsing/document"

module Kimera
  module Execution
  end
end

class Kimera::Execution::MacroLambdas
  def initialize(registry, root)
    @registry = registry
    @given = root
  end

  def quarantine!(coverage)
    @registry.to_h.each do |file, points|
      ranges = handed(file)
      points.each { |point| point.mark!(Kimera::Reason.macro.unless_covered(coverage, Kimera::Reason.kept)) if open?(point, ranges) }
    end
  end

  private

  def root = @_root ||= File.expand_path(@given)

  def open?(point, ranges)
    point.safe? && point.reasons(Kimera::Reason.revisiting).empty? && point.location.within?(ranges)
  end

  def handed(file) = lambdas(Kimera::Syntax::Document.new(root, file).result.value, argument: false)

  def lambdas(node, argument:)
    return [] if node.is_a?(Prism::DefNode)
    return [node.location] if argument && node.is_a?(Prism::LambdaNode)
    node.compact_child_nodes.flat_map { |child| lambdas(child, argument: argument || passed?(node, child)) }
  end

  def passed?(node, child) = node.is_a?(Prism::CallNode) && child.equal?(node.arguments)
end
