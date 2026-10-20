# frozen_string_literal: true

require_relative "memo_guard"
require_relative "support/branches"

class Kimera::FillGuard
  READ = Kimera::SyntaxTypes::InstanceVariableReadNode
  WRITE = Kimera::SyntaxTypes::InstanceVariableWriteNode
  NEGATIONS = %i[nil? !].freeze

  def initialize(statements)
    @statements = statements
  end

  def exemptions
    return [] unless @statements.size > 1 && name && fills? && tail?
    [
      Kimera::MemoGuard::Exemption.new(guard.location, Kimera::MemoGuard::CONDITIONAL),
      Kimera::MemoGuard::Exemption.new(store.location, Kimera::MemoGuard::ASSIGNMENT_DELETION)
    ]
  end

  private

  def guard = @statements.first

  def tail = @statements.last

  def name
    case guard
    when Kimera::SyntaxTypes::UnlessNode then read(guard.predicate) unless guard.else_clause
    when Kimera::SyntaxTypes::IfNode then negated(guard.predicate) unless Kimera::Branches.new(guard).following
    end
  end

  def read(node) = node.is_a?(READ) ? node.name : nil

  def negated(node)
    read(node.receiver) if node.is_a?(Kimera::SyntaxTypes::CallNode) && NEGATIONS.include?(node.name) && !node.arguments
  end

  def store = guard.statements&.body&.last

  def fills? = store.is_a?(WRITE) && store.name == name

  def tail? = tail.is_a?(READ) && tail.name == name
end
