# frozen_string_literal: true

require_relative "support/syntax"
require_relative "support/syntax_types"

class Kimera::MemoGuard
  CONDITIONAL = "conditional"
  BOOLEAN_LITERAL = "boolean_literal"
  ASSIGNMENT_DELETION = "assignment_deletion"
  READ = Kimera::SyntaxTypes::InstanceVariableReadNode
  WRITE = Kimera::SyntaxTypes::InstanceVariableWriteNode
  DEFINED = Kimera::SyntaxTypes::DefinedNode

  Exemption = Data.define(:location, :operator)

  def initialize(statements)
    @guard, @flag, *@rest = statements
  end

  def exemptions
    return [] unless name && (value? || flag?)
    [Exemption.new(@guard.location, CONDITIONAL), *followers]
  end

  private

  def name
    predicate = @guard.predicate if guard?
    predicate = predicate.value if predicate.is_a?(DEFINED)
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

  def followers
    stores = [@flag, *@rest].select { named?(it, WRITE) }.map { Exemption.new(it.location, ASSIGNMENT_DELETION) }
    flag? ? [Exemption.new(@flag.value.location, BOOLEAN_LITERAL), *stores] : stores
  end

  def named?(node, kind) = node.is_a?(kind) && node.name == name
end

require_relative "memo_guard_source"
