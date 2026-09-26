# frozen_string_literal: true

module Kimera::RegistryWalking
  PATTERN_HOLDERS = [
    Kimera::SyntaxTypes::InNode,
    Kimera::SyntaxTypes::MatchRequiredNode,
    Kimera::SyntaxTypes::MatchPredicateNode
  ].freeze

  Cursor = Data.define(:position, :inside_def, :in_pattern, :def_body, :defname)
  Shape =
    Data.define(:statements, :tail, :matchnode, :defbody, :insidedef) do
      def advance(child, cursor)
        cursor.with(
          position: position(child), inside_def: insidedef,
          in_pattern: cursor.in_pattern || child.equal?(matchnode), def_body: child.equal?(defbody)
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
    cursor = cursor.with(defname: node.name.to_s) if node.is_a?(Kimera::SyntaxTypes::DefNode)
    yield(node, cursor) unless cursor.in_pattern
    shape = shape(node, cursor)
    node.compact_child_nodes.each { |child| walk(child, shape.advance(child, cursor), &) }
  end

  def shape(node, cursor)
    statements = node.is_a?(Kimera::SyntaxTypes::StatementsNode) ? node.body : nil
    Shape.new(
      statements: statements, tail: cursor.def_body ? statements&.last : nil, matchnode: pattern(node),
      defbody: body(node), insidedef: cursor.inside_def || reexecuted?(node)
    )
  end

  def pattern(node)
    PATTERN_HOLDERS.any? { |k| node.is_a?(k) } ? node.pattern : nil
  end

  def body(node)
    node.is_a?(Kimera::SyntaxTypes::DefNode) ? node.body : nil
  end

  def reexecuted?(node)
    node.is_a?(Kimera::SyntaxTypes::DefNode) || node.is_a?(Kimera::SyntaxTypes::LambdaNode)
  end
end
