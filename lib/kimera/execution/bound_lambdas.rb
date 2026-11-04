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
  WRITES = [
    Prism::ConstantWriteNode, Prism::ConstantPathWriteNode, Prism::ConstantOrWriteNode, Prism::ConstantPathOrWriteNode
  ].freeze

  def initialize(registry, root)
    @registry = registry
    @root = root
  end

  def hold!(file)
    ranges = held(Kimera::Syntax::Document.new(@root, file).result.value)
    @registry.to_h.fetch(file, []).each { |point| point.mark!(Kimera::Reason.bound) if open?(point, ranges) }
  end

  private

  def held(node)
    return [node.value.location] if bound?(node)
    node.compact_child_nodes.flat_map { |child| held(child) }
  end

  def open?(point, ranges)
    point.reasons(Kimera::Reason.unreloadable).empty? && point.fits?(within: ranges)
  end

  def bound?(node) = WRITES.any? { |kind| node.is_a?(kind) } && callable?(node.value)

  def callable?(value) = value.is_a?(Prism::LambdaNode) || Kimera::Deferral.new(value).blocks.any?
end
