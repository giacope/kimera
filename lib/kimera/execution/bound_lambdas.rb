# frozen_string_literal: true

require "prism"
require_relative "../parsing/deferral"
require_relative "../parsing/document"
require_relative "../registry/mutation_point"

module Kimera
  module Execution
  end
end

class Kimera::Execution::BoundLambdas
  REASON = Kimera::MutationPoint::BOUND_REASON
  WRITES = [
    Prism::ConstantWriteNode, Prism::ConstantPathWriteNode, Prism::ConstantOrWriteNode, Prism::ConstantPathOrWriteNode
  ].freeze

  def initialize(registry, root)
    @registry = registry
    @root = root
  end

  def hold!(file)
    ranges = held(Kimera::Syntax::Document.new(@root, file).result.value)
    @registry.at(file).each { |point| point.unsafe!(REASON) if point.reloadable? && point.inside?(ranges) }
  end

  private

  def held(node)
    return [node.value.location] if bound?(node)
    node.compact_child_nodes.flat_map { |child| held(child) }
  end

  def bound?(node) = WRITES.any? { |kind| node.is_a?(kind) } && callable?(node.value)

  def callable?(value) = value.is_a?(Prism::LambdaNode) || !Kimera::Deferral.new(value).block.nil?
end
