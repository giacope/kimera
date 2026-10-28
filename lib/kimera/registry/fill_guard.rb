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
    return [] if @statements.size < 2
    names.select { |name| fills?(name) && tail?(name) }.flat_map do
      [
        Kimera::MemoGuard::Exemption.conditional(guard.location),
        *stores.map { |store| Kimera::MemoGuard::Exemption.deleted(store.location) }
      ]
    end
  end

  private

  def guard = @statements.fetch(0)

  def tail = @statements.fetch(-1)

  def names
    return [] unless CONDITIONALS.include?(guard.class) && !Kimera::Branches.new(guard).following
    guard.is_a?(Kimera::SyntaxTypes::UnlessNode) ? read(guard.predicate) : negated(guard.predicate)
  end

  def read(node) = node.is_a?(READ) ? [node.name] : []

  def negated(node)
    return [] unless node.is_a?(Kimera::SyntaxTypes::CallNode) && NEGATIONS.include?(node.name) && !node.arguments
    read(node.receiver)
  end

  def stores = Array(guard.statements&.body).last(1)

  def fills?(name) = stores.any? { |store| store.is_a?(WRITE) && store.name == name }

  def tail?(name) = tail.is_a?(READ) && tail.name == name
end
