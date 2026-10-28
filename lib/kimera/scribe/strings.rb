# frozen_string_literal: true

module Kimera
  class Scribe
    class Interpolated < Form
      TAIL = /\A[A-Za-z0-9_]/

      def word = inner(Words::BREAKS)

      private

      def inner(delimiter)
        pieces = segments
        pieces.each_with_index.sum("") { |piece, index| piece_text(piece, pieces[index + 1], delimiter) }
      end

      def segments
        runs = @node.parts.chunk_while { |left, right| [left, right].all? { |part| part.type == :string_node } }
        runs.map { |run| run.first.type == :string_node ? run.sum("") { |part| content(part) } : run.first }
      end

      def content(part) = part.unescaped

      def piece_text(piece, following, delimiter)
        piece.is_a?(::String) ? escaped(piece, delimiter) : embedded(piece, following)
      end

      def escaped(piece, delimiter) = Quote.new(piece, delimiter).text

      def embedded(node, following)
        return "##{part(node.variable)}" if node.type == :embedded_variable_node && !tail?(following)
        "\#{#{interpolation(node)}}"
      end

      def tail?(following) = following.is_a?(::String) && following.match?(TAIL)

      def interpolation(node) = pen_of(node).opened.write(node)
    end

    class Embedded < Form
      TYPES = %i[embedded_statements_node embedded_variable_node].freeze

      def text
        return part(@node.variable) if type == :embedded_variable_node
        @node.statements ? Sequence.new(@node.statements, @pen).text : ""
      end
    end

    class InterpolatedString < Interpolated
      TYPES = %i[interpolated_string_node].freeze

      def text
        return %("#{inner('"')}") unless juxtaposed?
        @node.parts.map { |piece| literal(piece) }.join(" ")
      end

      private

      def juxtaposed?
        @node.parts.any? do |piece|
          piece.type == :interpolated_string_node || (piece.type == :string_node && piece.opening_loc)
        end
      end

      def literal(piece)
        %i[string_node interpolated_string_node].include?(piece.type) ? part(piece) : %("\#{#{interpolation(piece)}}")
      end
    end

    class InterpolatedSymbol < Interpolated
      TYPES = %i[interpolated_symbol_node].freeze

      def text = %(:"#{inner('"')}")
    end

    class InterpolatedCommand < Interpolated
      TYPES = %i[interpolated_x_string_node].freeze

      def text = "`#{inner("`")}`"
    end

    class Pattern < Interpolated
      TYPES = %i[
        regular_expression_node interpolated_regular_expression_node match_last_line_node
        interpolated_match_last_line_node
      ].freeze
      PLAIN = %i[regular_expression_node match_last_line_node].freeze

      def text = "#{@node.opening}#{inner(@node.closing)}#{@node.closing}"

      private

      def segments = PLAIN.include?(type) ? [@node.content] : super

      def content(part)
        read = read_parts[@node.parts.index { |each| each.equal?(part) }]
        read&.type == :string_node && read.unescaped.b == part.unescaped.b ? part.content : "\#{#{part(part)}}"
      end

      def read_parts = @_read_parts ||= Kimera::Syntax.parse(@node.slice).value.statements.body.first.parts

      def escaped(piece, _delimiter) = piece
    end
  end
end
