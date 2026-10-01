# frozen_string_literal: true

class Kimera::DefaultRemoval::Source
  CALLABLES = Kimera::DefaultRemoval::CALLABLES

  def initialize(text)
    @text = text
  end

  def exemptions = signatures.flat_map(&:exemptions)

  def ranges = signatures.flat_map(&:ranges)

  private

  def signatures
    result = Kimera::Syntax.parse(@text)
    result.failure? ? [] : collect(result.value, [])
  end

  def collect(node, found)
    found << Kimera::DefaultRemoval.new(parameters(node), node.is_a?(Kimera::SyntaxTypes::BlockNode)) if callable?(node)
    node.compact_child_nodes.each { collect(it, found) }
    found
  end

  def callable?(node) = CALLABLES.any? { node.is_a?(it) } && node.parameters

  def parameters(callable)
    parameters = callable.parameters
    parameters.is_a?(Kimera::SyntaxTypes::BlockParametersNode) ? parameters.parameters : parameters
  end
end
