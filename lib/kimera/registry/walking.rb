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
      def self.origin
        new(position: nil, inside_def: nil, in_pattern: nil, def_body: nil, defname: nil, embedded: nil, block: nil)
      end

      def enter(node)
        return with(defname: node.name.to_s) if node.is_a?(Kimera::SyntaxTypes::DefNode)
        name = Kimera::Deferral.new(node).name
        return with(defname: name) if name
        holds?(node) ? with(block: node) : self
      end

      def open? = !in_pattern

      def moved(pattern:, **placed) = with(in_pattern: in_pattern || pattern, **placed)

      def shape(statements, reexecuted:, **facts)
        Shape.new(
          statements: embedded ? statements[...-1] : statements, tail: def_body ? statements&.last : nil,
          insidedef: inside_def || reexecuted, **facts
        )
      end

      def pairs(operators, node)
        admitted = operators.select { |operator| operator.reach.admits?(inside_def, position) }
        admitted.flat_map { |operator| operator.pairs(node, position: position) }
      end

      def held(operators, node)
        return [] unless block && !inside_def
        withheld = operators.select { |operator| operator.reach.withheld? }
        withheld.flat_map { |operator| operator.pairs(node, position: position) }.any? ? [[block, node]] : []
      end

      def named(attributes) = attributes.merge(method_name: defname)

      def classed(point, toggled) = inside_def || toggled ? point : point.tap { it.mark!(Kimera::Reason.class_body) }
      private
      def holds?(node) = !inside_def && !block && node.is_a?(Kimera::SyntaxTypes::BlockNode)
      private(*members)
    end
  Shape =
    Data.define(:statements, :tail, :matchnodes, :defbodies, :insidedef, :embeds, :deferred) do
      def advance(child, cursor)
        cursor.moved(
          position: position(child), inside_def: insidedef || deferred.any? { child.equal?(it) },
          pattern: matchnodes.any? { child.equal?(it) }, def_body: defbodies.any? { child.equal?(it) },
          embedded: embeds
        )
      end
      private
      def position(child)
        return :tail if child.equal?(tail)
        statements&.include?(child) || false
      end
      private(*members)
    end

  private

  def walk(node, cursor, &)
    return unless node.is_a?(Kimera::SyntaxTypes::Node)
    cursor = cursor.enter(node)
    yield(node, cursor) if cursor.open?
    shape = shape(node, cursor)
    node.compact_child_nodes.each { |child| walk(child, shape.advance(child, cursor), &) }
  end

  def shape(node, cursor)
    statements = node.is_a?(Kimera::SyntaxTypes::StatementsNode) ? node.body : nil
    cursor.shape(
      statements, matchnodes: patterns(node), defbodies: bodies(node), reexecuted: reexecuted?(node),
      embeds: node.is_a?(Kimera::SyntaxTypes::EmbeddedStatementsNode), deferred: deferred(node)
    )
  end

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
