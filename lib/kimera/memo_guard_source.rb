# frozen_string_literal: true

require_relative "fill_guard"

class Kimera::MemoGuard::Source
  def initialize(text)
    @text = text
  end

  def exemptions
    result = Kimera::Syntax.parse(@text)
    return [] if result.failure?
    defs(result.value).flat_map { guarded(statements(it.body)) }
  end

  private

  def guarded(body) = Kimera::MemoGuard.new(body).exemptions + Kimera::FillGuard.new(body).exemptions

  def statements(body) = body.is_a?(Kimera::SyntaxTypes::StatementsNode) ? body.body : []

  def defs(node)
    (node.is_a?(Kimera::SyntaxTypes::DefNode) ? [node] : []) + node.compact_child_nodes.flat_map { defs(it) }
  end
end
