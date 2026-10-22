# frozen_string_literal: true

module Kimera
  class Scribe
    class Interpolated < Form
      SIGILS = %i[ivar cvar gvar nth_ref back_ref].freeze
      TAIL = /\A[A-Za-z0-9_]/

      private

      def inner(delimiter, count = children.size)
        pieces = segments(count)
        pieces.each_with_index.sum("") { |piece, index| piece_text(piece, pieces[index + 1], delimiter) }
      end

      def segments(count)
        runs = children.first(count).each_with_index.chunk_while { |(left, _), (right, _)| joinable?(left, right) }
        runs.map do |run|
          if run.first.first.type == :str
            run.sum("") do |(node, _)|
              node.children.first
            end
          else
            run.first.last
          end
        end
      end

      def joinable?(left, right)
        [left, right].all? { |node| node.type == :str } && !left.children.first.end_with?("\n")
      end

      def piece_text(piece, following, delimiter)
        return embedded(piece, following) if piece.is_a?(Integer)
        return Quote.new(piece, delimiter).text unless piece.end_with?("\n") && following.is_a?(::String)
        "#{Quote.new(piece.chomp, delimiter).text}\n"
      end

      def embedded(index, following)
        node = children.fetch(index)
        bare = SIGILS.include?(node.type) && !(following.is_a?(::String) && following.match?(TAIL))
        bare ? "##{part(index)}" : "\#{#{interpolation(index)}}"
      end

      def interpolation(index)
        pen = pens.fetch(index).opened
        node = children.fetch(index)
        node.type == :begin ? Sequence.new(node, pen).text : pen.write(node)
      end
    end

    class Dstr < Interpolated
      TYPES = %i[dstr].freeze

      def text
        return '""' if children.empty?
        return %("#{inner('"')}") unless juxtaposed?
        children.each_index.map { |index| literal(index) }.join(" ")
      end

      private

      def juxtaposed? = children.any? { |child| child.type == :dstr } || children.all? { |child| child.type == :str }

      def literal(index)
        %i[str dstr].include?(children.fetch(index).type) ? part(index) : %("\#{#{interpolation(index)}}")
      end
    end

    class Dsym < Interpolated
      TYPES = %i[dsym].freeze

      def text = %(:"#{inner('"')}")
    end

    class Xstr < Interpolated
      TYPES = %i[xstr].freeze

      def text = "`#{inner("`")}`"
    end

    class RegularExpression < Interpolated
      TYPES = %i[regexp].freeze
      DELIMITERS = [%w[/ /], %w[{ }], %w[[ ]], %w[( )], %w[< >], %w[| |], %w[! !]].freeze
      SLASH = %r{(?<!\\)((?:\\\\)*)/}

      def text
        open, close = delimiters
        "#{"%r" unless open == "/"}#{open}#{inner(close, children.size - 1)}#{close}#{children.last.children.join}"
      end

      private

      def piece_text(piece, following, delimiter)
        return embedded(piece, following) if piece.is_a?(Integer)
        delimiter == "/" ? piece.gsub(SLASH) { "#{::Regexp.last_match(1)}\\/" } : piece
      end

      def delimiters
        raw = children.select { |child| child.type == :str }.sum("") { |child| child.children.first }
        DELIMITERS.find { |pair| pair.none? { |mark| raw.include?(mark) } } || DELIMITERS.first
      end
    end
  end
end
