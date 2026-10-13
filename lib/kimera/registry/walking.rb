# frozen_string_literal: true

require_relative "../support/deferral"

module Kimera::RegistryWalking
  PATTERN_HOLDERS = [
    Kimera::SyntaxTypes::InNode,
    Kimera::SyntaxTypes::MatchRequiredNode,
    Kimera::SyntaxTypes::MatchPredicateNode
  ].freeze

  Cursor = Data.define(:position, :inside_def, :in_pattern, :def_body, :defname, :embedded, :block)
  Shape =
    Data.define(:statements, :tail, :matchnode, :defbody, :insidedef, :embeds, :deferred) do
      def advance(child, cursor)
        cursor.with(
          position: position(child), inside_def: insidedef || child.equal?(deferred),
          in_pattern: cursor.in_pattern || child.equal?(matchnode), def_body: child.equal?(defbody),
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
    cursor = entered(node, cursor)
    yield(node, cursor) unless cursor.in_pattern
    shape = shape(node, cursor)
    node.compact_child_nodes.each { |child| walk(child, shape.advance(child, cursor), &) }
  end

  def entered(node, cursor)
    return cursor.with(defname: node.name.to_s) if node.is_a?(Kimera::SyntaxTypes::DefNode)
    name = Kimera::Deferral.name(node)
    return cursor.with(defname: name) if name
    held?(node, cursor) ? cursor.with(block: node) : cursor
  end

  def held?(node, cursor) = !cursor.inside_def && !cursor.block && node.is_a?(Kimera::SyntaxTypes::BlockNode)

  def shape(node, cursor)
    statements = node.is_a?(Kimera::SyntaxTypes::StatementsNode) ? node.body : nil
    Shape.new(
      statements: deletable(statements, cursor), tail: cursor.def_body ? statements&.last : nil,
      matchnode: pattern(node), defbody: body(node), insidedef: cursor.inside_def || reexecuted?(node),
      embeds: node.is_a?(Kimera::SyntaxTypes::EmbeddedStatementsNode), deferred: deferred(node)
    )
  end

  def deletable(statements, cursor) = cursor.embedded ? statements[...-1] : statements

  def pattern(node)
    PATTERN_HOLDERS.any? { |k| node.is_a?(k) } ? node.pattern : nil
  end

  def body(node)
    node.is_a?(Kimera::SyntaxTypes::DefNode) ? node.body : nil
  end

  def reexecuted?(node)
    node.is_a?(Kimera::SyntaxTypes::DefNode) || node.is_a?(Kimera::SyntaxTypes::LambdaNode)
  end

  def deferred(node) = Kimera::Deferral.block(node)
end
