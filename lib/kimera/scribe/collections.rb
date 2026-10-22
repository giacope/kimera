# frozen_string_literal: true

module Kimera
  class Scribe
    class Sequence < Form
      TYPES = [].freeze

      def text = children.each_index.map { |index| pens.fetch(index).opened.write(children.fetch(index)) }.join("; ")
    end

    class Parentheses < Form
      TYPES = %i[begin].freeze

      def text = enclosed(Sequence)
    end

    class Elements < Form
      TYPES = %i[array].freeze

      def text = "[#{rest(0)}]"
    end

    class Arguments < Form
      TYPES = %i[kwargs].freeze

      def text = rest(0)
    end

    class Pairs < Form
      TYPES = %i[hash].freeze

      def text = children.empty? ? "{}" : "{ #{rest(0)} }"
    end

    class Pair < Form
      TYPES = %i[pair].freeze

      def text
        key = children.first
        written = part(1, Level::ASSIGNMENT)
        case key.type
        when :sym then labelled(key.children.first, written)
        when :dsym then "#{part(0).delete_prefix(":")}: #{written}"
        else "#{leading(0, Level::RANGE)} => #{written}"
        end
      end

      private

      def labelled(name, written)
        shorthand = written == name.to_s && %i[lvar send].include?(children[1].type)
        shorthand ? "#{name}:" : "#{Name.new(name).label} #{written}"
      end
    end

    class Splat < Form
      TYPES = %i[splat kwsplat block_pass].freeze
      PREFIXES = { splat: "*", kwsplat: "**", block_pass: "&" }.freeze

      def text = "#{PREFIXES.fetch(type)}#{part(0, Level::ASSIGNMENT) if children.first}"
    end

    class Span < Form
      TYPES = %i[irange erange iflipflop eflipflop].freeze
      OPERATORS = { irange: "..", erange: "...", iflipflop: "..", eflipflop: "..." }.freeze

      def text
        first, last = children
        floor = Level::RANGE + 1
        "#{leading(0, floor) if first}#{OPERATORS.fetch(type)}#{trailing(1, floor) if last}"
      end

      def level = Level::RANGE
    end
  end
end
