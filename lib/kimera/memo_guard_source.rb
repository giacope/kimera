# frozen_string_literal: true

class Kimera::MemoGuard::Source
  def initialize(text)
    @text = text
  end

  def exemptions
    result = Kimera::Syntax.parse(@text)
    return [] if result.failure?
    defs(result.value).flat_map { Kimera::MemoGuard.new(statements(it.body)).exemptions }
  end

  private

  def statements(body) = body.is_a?(Kimera::SyntaxTypes::StatementsNode) ? body.body : []

  def defs(node, found = [])
    found << node if node.is_a?(Kimera::SyntaxTypes::DefNode)
    node.compact_child_nodes.each { defs(it, found) }
    found
  end
end
