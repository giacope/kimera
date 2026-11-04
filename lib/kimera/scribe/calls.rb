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
          kind.new(@node, @pen, @scope, @mode)
        end.lazy.select(&:fits?).first(1).fetch(0)
      end
    end

    class Operation < Form
      def fits? = Shape.new(@node).binary?

      def level = BINARY.fetch(@node.name)

      def text = "#{left} #{@node.name} #{operand(Operands.new(@node).to_a.first, power? ? level : level + 1)}"

      private

      def power? = @node.name == :**

      def left
        receiver = @node.receiver
        written = leading(receiver, power? || NONASSOCIATIVE.include?(level) ? level + 1 : level)
        power? && Token.new(receiver).numeral? && written.start_with?("-") ? "(#{written})" : written
      end
    end

    class Unary < Form
      SIGNS = %i[-@ +@].freeze
      LEADING = /\A[0-9]/

      def fits? = Shape.new(@node).prefix?

      def level = PREFIX.fetch(@node.name)

      def text
        written = operand(@node.receiver, level)
        "#{@node.name.to_s.delete_suffix("@")}#{fused?(written) ? "(#{written})" : written}"
      end

      private

      def fused?(written) = SIGNS.include?(@node.name) && written.match?(LEADING)
    end

    class Negation < Form
      def fits? = Shape.new(@node).prefix? && Token.new(@node).spelled?("not")

      def level = EXPRESSION

      def text
        receiver = @node.receiver
        written = unbraced(receiver)
        written == part(receiver) ? "not #{written}" : "not#{written}"
      end

      private

      def unbraced(receiver)
        form_of(receiver).level == KEYWORD ? part(receiver, TERNARY) : trailing(receiver, ASSIGNMENT)
      end
    end

    class Setting < Form
      def fits? = Shape.new(@node).setter?

      def level = ASSIGNMENT

      def text
        value = Operands.new(@node).to_a.last
        dot = @node.safe_navigation? ? "&." : "."
        owner = @node.receiver ? receiver_part(@node.receiver) : "self"
        "#{owner}#{dot}#{@node.name.to_s.delete_suffix("=")} = #{part(value, value_floor(value))}"
      end
    end

    class Indexing < Form
      def fits? = %i[[] []=].include?(@node.name) && @node.receiver && !@node.call_operator_loc

      def level = @node.name == :[] ? PRIMARY : ASSIGNMENT

      def text
        *keys, value = Operands.new(@node).to_a
        return "#{head(keys)} = #{part(value, value_floor(value))}" unless @node.name == :[]
        "#{head([*keys, value].compact)}#{Block.new(@node.block, @pen, @scope, @mode).suffix if literal_block}"
      end

      private

      def head(keys) = "#{receiver_part(@node.receiver)}[#{listed([*keys, block_argument].compact)}]"
    end

    class Message < Form
      CAPITAL = /\A[A-Z]/

      def fits? = true

      def text = "#{head}#{arguments}#{attached(literal_block) if literal_block}"

      private

      def head
        receiver = @node.receiver
        name = @node.name
        receiver ? "#{receiver_part(receiver)}#{dot}#{name}" : name.to_s
      end

      def dot = @node.safe_navigation? ? "&." : "."

      def arguments
        listing = present([@node.arguments, block_argument])
        return "(#{listing.map { |node| part(node) }.join(", ")})" if listing.any?
        bare? ? "" : "()"
      end

      def bare?
        name = @node.name
        return true if @node.receiver
        return false if @scope.local?(name) || name.match?(CAPITAL)
        @node.variable_call? || literal_block || name.end_with?("?", "!")
      end
    end

    class Invocation < Form
      TYPES = %i[yield_node super_node defined_node forwarding_super_node].freeze
      WORDS = { yield_node: "yield", super_node: "super" }.freeze

      def text
        return "super#{suffix}" if type == :forwarding_super_node
        return "defined?(#{part(@node.value, ASSIGNMENT)})" if type == :defined_node
        listing.empty? && type == :yield_node ? "yield" : "#{WORDS.fetch(type)}(#{listed_parts})#{suffix}"
      end

      private

      def listing = present([@node.arguments, (@node.block if block_argument?)])

      def listed_parts = listing.map { |node| part(node) }.join(", ")

      def block_argument? = @node.respond_to?(:block) && @node.block&.type == :block_argument_node

      def suffix
        block = @node.block if @node.respond_to?(:block)
        block&.type == :block_node ? attached(block) : ""
      end
    end
  end
end
