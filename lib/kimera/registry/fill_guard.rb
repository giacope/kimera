# frozen_string_literal: true

require_relative "memo_guard"
require_relative "../parsing/branches"

class Kimera::FillGuard
  READ = Kimera::SyntaxTypes::InstanceVariableReadNode
  WRITE = Kimera::SyntaxTypes::InstanceVariableWriteNode
  NEGATIONS = %i[nil? !].freeze
  CONDITIONALS = [Kimera::SyntaxTypes::IfNode, Kimera::SyntaxTypes::UnlessNode].freeze

  def initialize(statements)
    @statements = statements
  end

  def exemptions
    return [] unless name && fills? && tail?
    [
      Kimera::MemoGuard::Exemption.conditional(guard.location),
      Kimera::MemoGuard::Exemption.deleted(store.location)
    ]
  end

  private

  def guard = @statements.first

  def tail = @statements.last

  def name
    return unless CONDITIONALS.include?(guard.class) && !Kimera::Branches.new(guard).following
    guard.is_a?(Kimera::SyntaxTypes::UnlessNode) ? read(guard.predicate) : negated(guard.predicate)
  end

  def read(node) = node.is_a?(READ) ? node.name : nil

  def negated(node)
    read(node.receiver) if node.is_a?(Kimera::SyntaxTypes::CallNode) && NEGATIONS.include?(node.name) && !node.arguments
  end

  def store = guard.statements&.body&.last

  def fills? = store.is_a?(WRITE) && store.name == name

  def tail? = tail.is_a?(READ) && tail.name == name
end
