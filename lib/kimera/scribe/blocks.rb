# frozen_string_literal: true

require_relative "default_locals"

module Kimera
  class Scribe
    class Closure < Form
      private

      def closure = @_closure ||= DefaultLocals.new(@node, @scope).node

      def parameters
        node = closure.parameters
        explicit = node&.type == :block_parameters_node
        locals = shadowed
        return unless explicit || locals.any?
        own = explicit ? part(node) : ""
        separator = explicit && node.locals.any? ? ", " : "; "
        appended(own, locals.join(", "), separator)
      end

      def shadowed
        node = closure
        declared = @scope.scoped([node.parameters])
        node.locals.select { |name| @scope.local?(name) && !declared.local?(name) }
      end
    end

    class Block < Closure
      def suffix
        node = closure
        kept = @pen.slice(node, @scope) { return braced(node.body, @scope.with([node.parameters]), bars) }
        " #{kept}"
      end

      private

      def bars
        written = parameters
        written ? " |#{written}|" : ""
      end
    end

    class Lambda < Closure
      TYPES = %i[lambda_node].freeze

      def text
        written = parameters
        listed = written ? "(#{written})" : ""
        node = closure
        "->#{listed}#{braced(node.body, @scope.with([node.parameters]))}"
      end
    end

    class BlockParameters < Form
      TYPES = %i[block_parameters_node].freeze

      def text
        own = @node.parameters ? part(@node.parameters) : ""
        appended(own, listed(@node.locals), "; ")
      end
    end

    class Parameters < Form
      TYPES = %i[parameters_node].freeze
      FIELDS = %i[requireds optionals rest posts keywords keyword_rest block].freeze

      def text
        trailed(FIELDS.flat_map { |field| Array(@node.public_send(field)) })
      end
    end

    class Parameter < Form
      TYPES = %i[
        optional_parameter_node rest_parameter_node required_keyword_parameter_node
        optional_keyword_parameter_node keyword_rest_parameter_node block_parameter_node
      ].freeze
      PREFIXES = { rest_parameter_node: "*", keyword_rest_parameter_node: "**", block_parameter_node: "&" }.freeze
      SUFFIXES = {
        optional_parameter_node: " = ", optional_keyword_parameter_node: ": ", required_keyword_parameter_node: ":"
      }.freeze

      def text = "#{PREFIXES[type]}#{@node.name}#{SUFFIXES[type]}#{default if @node.respond_to?(:value)}"

      private

      def default
        bound(@node.value, Set[@node.name], ASSIGNMENT)
      end
    end
  end
end
