# frozen_string_literal: true

require_relative "../rewrite/ast_walk"
require_relative "../scribe/nodes"

class Kimera::Unguarded
  include Kimera::Scribe::Nodes

  RUNTIME = %i[active? privatize].freeze
  CAUGHT = "*(::Kimera::RUNTIME.active?("

  def initialize(node)
    @node = node
  end

  def node = Kimera::Rewrite::AstWalk.new(@node).rebuild { |rebuilt, original| unguarded(rebuilt, original) }

  private

  def unguarded(rebuilt, original)
    return side(rebuilt) if guard?(rebuilt)
    return statements(rebuilt.statements.body) if inverted?(original)
    return Kimera::Unguarded::Caught.new(rebuilt).clause if clause?(original)
    rebuilt.type == :statements_node ? kept(rebuilt, original) : rebuilt
  end

  def clause?(node) = node.type == :rescue_node && node.exceptions.first&.slice&.start_with?(CAUGHT)

  def kept(rebuilt, original)
    pairs = rebuilt.body.zip(original.body).reject { |node, was| runtime?(node) || probe?(was) }
    rebuilt.copy(body: pairs.flat_map { |node, _| node.type == :statements_node ? node.body : [node] })
  end

  def side(guard) = statements(guard.subsequent&.statements&.body || [])

  def guard?(node) = node.type == :if_node && runtime?(node.predicate)

  def inverted?(node) = node.type == :if_node && negation?(node.predicate)

  def negation?(node) = node.type == :call_node && node.name == :! && tested?(node.receiver)

  def tested?(node) = runtime?(node) || either?(node) || held?(node)

  def either?(node) = node.type == :or_node && tested?(node.left) && tested?(node.right)

  def held?(node) = node.type == :parentheses_node && node.body&.body&.one? && tested?(node.body.body.first)

  def probe?(node) = guard?(node) && [node.statements, node.subsequent&.statements].all? { |each| empty?(each) }

  def empty?(statements)
    body = statements&.body || []
    body.one? && (body.first.type == :nil_node || probe?(body.first))
  end

  def runtime?(node)
    receiver = node.receiver if node.type == :call_node
    receiver&.type == :constant_path_node && receiver.name == :RUNTIME && RUNTIME.include?(node.name)
  end
end

Kimera::Unguarded::Caught =
  Data.define(:guarded) do
    def clause = guarded.copy(exceptions: listed.type == :array_node ? listed.elements : [])

    def listed = guarded.exceptions.first.expression.body.body.first
  end
