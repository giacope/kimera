# frozen_string_literal: true

require "prism"
require_relative "../parsing/deferral"
require_relative "../parsing/document"
require_relative "../registry/mutation_point"

module Kimera
  module Execution
  end
end

# A lambda or proc a constant holds was made once, at load, and whatever the
# suite took from the constant then (`self.chain = [BY_SYMBOL]`) keeps that
# object. Kimera cannot weave guards into it, and binding the constant to a
# guarded copy would leave the registry calling the original, so the copy's
# coverage read "no test executed this line". The constant stays bound; its
# body is judged in the isolated tier, like other code that ran at load. So
# are its parameters' defaults (`strict: false`), which a constant's value
# taints for the reload tier: reloading the file binds a new lambda the
# registry never calls either, so their mutants survived.
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
