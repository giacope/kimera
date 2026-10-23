# frozen_string_literal: true

module Kimera
  class Scribe
    class Call < Form
      TYPES = %i[call_node].freeze

      def text = variant.text

      def level = variant.level

      private

      def variant
        @_variant ||= [Negation, Operation, Unary, Setting, Indexing, Message].map do |kind|
          kind.new(@node, @pen)
        end.find(&:fits?)
      end
    end

    class Operation < Form
      def fits? = Shape.new(@node).binary?

      def level = Level::BINARY.fetch(@node.name)

      def text = "#{left} #{@node.name} #{operand(Shape.new(@node).arguments.first, power? ? level : level + 1)}"

      private

      def power? = @node.name == :**

      def left
        receiver = @node.receiver
        written = leading(receiver, power? || Level::NONASSOCIATIVE.include?(level) ? level + 1 : level)
        power? && Shape.new(receiver).numeral? && written.start_with?("-") ? "(#{written})" : written
      end
    end

    class Unary < Form
      SIGNS = %i[-@ +@].freeze
      LEADING = /\A[0-9]/

      def fits? = Shape.new(@node).prefix?

      def level = Level::PREFIX.fetch(@node.name)

      def text
        written = operand(@node.receiver, level)
        "#{@node.name.to_s.delete_suffix("@")}#{fused?(written) ? "(#{written})" : written}"
      end

      private

      def fused?(written) = SIGNS.include?(@node.name) && written.match?(LEADING) && !Shape.new(@node.receiver).numeral?
    end

    class Negation < Form
      def fits? = Shape.new(@node).prefix? && Shape.new(@node).spelled?("not")

      def level = Level::EXPRESSION

      def text
        receiver = @node.receiver
        written = unbraced(receiver)
        receiver.type != :parentheses_node && written.start_with?("(") ? "not#{written}" : "not #{written}"
      end

      private

      def unbraced(receiver)
        keyword = pen_of(receiver).level(receiver) == Level::KEYWORD
        keyword ? part(receiver, Level::TERNARY) : trailing(receiver, Level::ASSIGNMENT)
      end
    end

    class Setting < Form
      def fits? = Shape.new(@node).setter?

      def level = Level::ASSIGNMENT

      def text
        value = Shape.new(@node).arguments.last
        dot = @node.safe_navigation? ? "&." : "."
        owner = @node.receiver ? receiver_part(@node.receiver) : "self"
        "#{owner}#{dot}#{@node.name.to_s.delete_suffix("=")} = #{part(value, value_floor(value))}"
      end
    end

    class Indexing < Form
      def fits? = %i[[] []=].include?(@node.name) && @node.receiver && !@node.call_operator_loc

      def level = @node.name == :[] ? Level::PRIMARY : Level::ASSIGNMENT

      def text
        *keys, value = Shape.new(@node).arguments
        return "#{head(keys)} = #{part(value, value_floor(value))}" unless @node.name == :[]
        "#{head([*keys, value].compact)}#{Block.new(@node.block, @pen).suffix if literal_block}"
      end

      private

      def head(keys) = "#{receiver_part(@node.receiver)}[#{listed([*keys, block_argument].compact)}]"
    end

    class Message < Form
      CAPITAL = /\A[A-Z]/

      def fits? = true

      def text = "#{head}#{arguments}#{Block.new(literal_block, pen_of(literal_block)).suffix if literal_block}"

      private

      def head
        receiver = @node.receiver
        name = @node.name
        receiver ? "#{receiver_part(receiver)}#{dot}#{name}" : name.to_s
      end

      def dot = @node.safe_navigation? ? "&." : "."

      def arguments
        listing = [@node.arguments, block_argument].compact
        return "(#{listing.map { |node| part(node) }.join(", ")})" if listing.any?
        bare? ? "" : "()"
      end

      def bare?
        name = @node.name
        return true if @node.receiver
        return false if @pen.local?(name) || name.match?(CAPITAL)
        @node.variable_call? || literal_block || name.end_with?("?", "!")
      end
    end

    class Invocation < Form
      TYPES = %i[yield_node super_node defined_node forwarding_super_node].freeze
      WORDS = { yield_node: "yield", super_node: "super" }.freeze

      def text
        return "super#{suffix}" if type == :forwarding_super_node
        return "defined?(#{part(@node.value, Level::ASSIGNMENT)})" if type == :defined_node
        listing.empty? && type == :yield_node ? "yield" : "#{WORDS.fetch(type)}(#{listed_parts})#{suffix}"
      end

      private

      def listing = [@node.arguments, (@node.block if block_argument?)].compact

      def listed_parts = listing.map { |node| part(node) }.join(", ")

      def block_argument? = @node.respond_to?(:block) && @node.block&.type == :block_argument_node

      def suffix
        block = @node.block if @node.respond_to?(:block)
        block&.type == :block_node ? Block.new(block, pen_of(block)).suffix : ""
      end
    end
  end
end
