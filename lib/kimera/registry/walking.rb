# frozen_string_literal: true

require_relative "../parsing/deferral"

module Kimera::RegistryWalking
  PATTERN_HOLDERS = [
    Kimera::SyntaxTypes::InNode,
    Kimera::SyntaxTypes::MatchRequiredNode,
    Kimera::SyntaxTypes::MatchPredicateNode
  ].freeze

  Cursor =
    Data.define(:position, :inside_def, :in_pattern, :def_body, :defname, :embedded, :block) do
      def enter(node)
        return with(defname: node.name.to_s) if node.is_a?(Kimera::SyntaxTypes::DefNode)
        name = Kimera::Deferral.new(node).name
        return with(defname: name) if name
        holds?(node) ? with(block: node) : self
      end

      def holds?(node) = !inside_def && !block && node.is_a?(Kimera::SyntaxTypes::BlockNode)
    end
  Shape =
    Data.define(:statements, :tail, :matchnodes, :defbodies, :insidedef, :embeds, :deferred) do
      def advance(child, cursor)
        cursor.with(
          position: position(child), inside_def: insidedef || deferred.any? { child.equal?(it) },
          in_pattern: cursor.in_pattern || matchnodes.any? { child.equal?(it) },
          def_body: defbodies.any? { child.equal?(it) },
          embedded: embeds
        )
      end

      def position(child)
        return :tail if child.equal?(tail)
        statements&.include?(child) || false
      end
    end

  private

  def walk(node, cursor, &)
    return unless node.is_a?(Kimera::SyntaxTypes::Node)
    cursor = cursor.enter(node)
    yield(node, cursor) unless cursor.in_pattern
    shape = shape(node, cursor)
    node.compact_child_nodes.each { |child| walk(child, shape.advance(child, cursor), &) }
  end

  def shape(node, cursor)
    statements = node.is_a?(Kimera::SyntaxTypes::StatementsNode) ? node.body : nil
    Shape.new(
      statements: deletable(statements, cursor), tail: cursor.def_body ? statements&.last : nil,
      matchnodes: patterns(node), defbodies: bodies(node), insidedef: cursor.inside_def || reexecuted?(node),
      embeds: node.is_a?(Kimera::SyntaxTypes::EmbeddedStatementsNode), deferred: deferred(node)
    )
  end

  def deletable(statements, cursor) = cursor.embedded ? statements[...-1] : statements

  def patterns(node)
    PATTERN_HOLDERS.any? { |k| node.is_a?(k) } ? [node.pattern] : []
  end

  def bodies(node)
    node.is_a?(Kimera::SyntaxTypes::DefNode) ? [node.body] : []
  end

  def reexecuted?(node)
    node.is_a?(Kimera::SyntaxTypes::DefNode) || node.is_a?(Kimera::SyntaxTypes::LambdaNode)
  end

  def deferred(node) = Kimera::Deferral.new(node).blocks
end
