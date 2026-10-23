# frozen_string_literal: true

module Kimera
  class Scribe
    class Block < Form
      def suffix
        kept = @pen.slice(@node)
        kept ? " #{kept}" : braced(@node.body, @pen.with([@node.parameters]), bars)
      end

      private

      def bars
        parameters = @node.parameters
        parameters&.type == :block_parameters_node ? " |#{part(parameters)}|" : ""
      end
    end

    class Lambda < Form
      TYPES = %i[lambda_node].freeze

      def text
        parameters = @node.parameters
        listed = parameters&.type == :block_parameters_node ? "(#{part(parameters)})" : ""
        "->#{listed}#{braced(@node.body, @pen.with([parameters]))}"
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
        value = @node.value
        pen_of(value).bound(Set[@node.name]).write(value, Level::ASSIGNMENT)
      end
    end
  end
end
