# frozen_string_literal: true

module Kimera
  class Scribe
    class Call < Form
      TYPES = %i[send csend].freeze

      def text = variant.text

      def level = variant.level

      def regular = Message.new(@node, @pen).text

      private

      def variant
        @_variant ||= [Negation, Operation, Unary, AttributeAssignment, Message].map do |kind|
          kind.new(@node, @pen)
        end.find(&:fits?)
      end
    end

    class Operation < Form
      def fits? = type == :send && children.first && Level::BINARY.key?(children[1]) && Shape.new(@node).single?

      def level = Level::BINARY.fetch(children[1])

      def text = "#{left} #{children[1]} #{operand(2, power? ? level : level + 1)}"

      private

      def power? = children[1] == :**

      def left
        written = leading(0, power? || Level::NONASSOCIATIVE.include?(level) ? level + 1 : level)
        power? && Shape.new(children.first).numeral? && written.start_with?("-") ? "(#{written})" : written
      end
    end

    class Unary < Form
      SIGNS = %i[-@ +@].freeze
      LEADING = /\A[0-9]/

      def fits? = children.first && Shape.new(@node).prefix?

      def level = Level::PREFIX.fetch(children[1])

      def text
        written = operand(0, level)
        "#{children[1].to_s.delete_suffix("@")}#{fused?(written) ? "(#{written})" : written}"
      end

      private

      def fused?(written)
        SIGNS.include?(children[1]) && written.match?(LEADING) && !Shape.new(children.first).numeral?
      end
    end

    class Negation < Form
      def fits? = Shape.new(@node).prefix? && Shape.new(@node).spelled?("not")

      def level = Level::EXPRESSION

      def text
        written = trailing(0, Level::ASSIGNMENT)
        children.first.type != :begin && written.start_with?("(") ? "not#{written}" : "not #{written}"
      end
    end

    class AttributeAssignment < Form
      def fits? = Shape.new(@node).setter?

      def level = Level::ASSIGNMENT

      def text = "#{Attribute.new(@node, @pen).text} = #{part(2, value_floor(children[2]))}"
    end

    class Message < Form
      CAPITAL = /\A[A-Z]/

      def fits? = true

      def text
        receiver, selector = children
        head =
          if receiver
            "#{receiver_part(0)}#{type == :csend ? "&." : "."}#{selector}"
          else
            selector.to_s
          end
        "#{head}#{arguments}"
      end

      private

      def arguments
        receiver, selector = children
        return "(#{rest(2)})" if children.size > 2
        receiver || !(@pen.local?(selector) || selector.match?(CAPITAL)) ? "" : "()"
      end
    end

    class Index < Form
      TYPES = %i[index].freeze

      def text = "#{receiver_part(0)}[#{rest(1)}]"
    end

    class Invocation < Form
      TYPES = %i[yield super defined?].freeze

      def text
        type == :yield && children.empty? ? "yield" : "#{type}(#{rest(0)})"
      end
    end
  end
end
