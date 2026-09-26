# frozen_string_literal: true

require_relative "support/syntax"
require_relative "support/syntax_types"

class Kimera::MemoGuard
  CONDITIONAL = "conditional"
  BOOLEAN_LITERAL = "boolean_literal"
  READ = Kimera::SyntaxTypes::InstanceVariableReadNode
  WRITE = Kimera::SyntaxTypes::InstanceVariableWriteNode

  Exemption = Data.define(:location, :operator)

  class << self
    def exemptions(source)
      result = Kimera::Syntax.parse(source)
      return [] if result.failure?
      defs(result.value).flat_map { new(statements(it.body)).exemptions }
    end

    def statements(body) = body.is_a?(Kimera::SyntaxTypes::StatementsNode) ? body.body : []

    def defs(node, found = [])
      found << node if node.is_a?(Kimera::SyntaxTypes::DefNode)
      node.compact_child_nodes.each { defs(it, found) }
      found
    end
  end

  def initialize(statements)
    @guard, @flag, *@rest = statements
  end

  def exemptions
    return [] unless name && (value? || flag?)
    [Exemption.new(@guard.location, CONDITIONAL), *raised]
  end

  private

  def name
    predicate = @guard.predicate if guard?
    predicate.name if predicate.is_a?(READ)
  end

  def guard? = @guard.is_a?(Kimera::SyntaxTypes::IfNode) && @guard.compact_child_nodes.size == 2 && returns?

  def returns? = @guard.statements.body.size == 1 && returned.is_a?(Kimera::SyntaxTypes::ReturnNode)

  def returned = @guard.statements.body.first

  def value? = caches? && [@flag, *@rest].any? { named?(it, WRITE) }

  def caches?
    values = returned.arguments&.arguments
    values&.size == 1 && named?(values.first, READ)
  end

  def flag? = returned.compact_child_nodes.empty? && raises?

  def raises? = named?(@flag, WRITE) && @flag.value.is_a?(Kimera::SyntaxTypes::TrueNode)

  def raised = flag? ? [Exemption.new(@flag.value.location, BOOLEAN_LITERAL)] : []

  def named?(node, kind) = node.is_a?(kind) && node.name == name
end
