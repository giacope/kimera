# frozen_string_literal: true

module Kimera
  class Scribe
    class Bracketed < Form
      TYPES = %i[begin_node].freeze

      def text = "begin#{Clauses.new(@node, @pen).structure}#{closing}"

      def level = Level::KEYWORD
    end

    class Rescued < Form
      TYPES = %i[rescue_modifier_node].freeze

      def text
        body = @node.expression
        written = Jump::TYPES.include?(body.type) ? part(body) : leading(body, Level::TERNARY)
        "#{written} rescue #{part(@node.rescue_expression, Level::EXPRESSION)}"
      end

      def level = Level::STATEMENT
    end

    class Exceptions < Form
      def text = @node.exceptions.map { |exception| item(exception) }.join(", ")

      private

      def item(exception)
        return pen_of(exception).form(exception).ternary if %i[if_node unless_node].include?(exception.type)
        part(exception, Level::ASSIGNMENT)
      end
    end

    class Rescue < Form
      def text = "#{newline}#{head}#{body}"

      private

      def head
        exceptions = @node.exceptions
        target = @node.reference
        written = exceptions.any? ? "rescue #{Exceptions.new(@node, @pen).text}" : "rescue"
        target ? "#{written} => #{@pen.with(exceptions).write(target)}" : written
      end

      def body = Lines.new(@node.statements, @pen.with([*@node.exceptions, @node.reference]).deeper).text
    end

    class Exchange < Form
      TYPES = %i[alias_method_node alias_global_variable_node undef_node].freeze

      def text
        return "undef #{@node.names.map { |name| part(name) }.join(", ")}" if type == :undef_node
        "alias #{part(@node.new_name)} #{part(@node.old_name)}"
      end

      def level = Level::STATEMENT
    end

    class Hook < Form
      TYPES = %i[pre_execution_node post_execution_node].freeze

      def text = "#{type == :pre_execution_node ? "BEGIN" : "END"} {#{lines(@node.statements)}#{closing("}")}"

      def level = Level::STATEMENT
    end

    class Capture < Form
      TYPES = %i[match_write_node].freeze

      def text = part(@node.call)

      def level = Level::EQUALITY
    end

    class Shareable < Form
      TYPES = %i[shareable_constant_node].freeze

      def text = part(@node.write)

      def level = Level::ASSIGNMENT
    end
  end
end
