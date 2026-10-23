# frozen_string_literal: true

module Kimera
  class Scribe
    class Keyword < Form
      WORDS = {
        true_node: "true", false_node: "false", nil_node: "nil", self_node: "self", source_file_node: "__FILE__",
        source_line_node: "__LINE__", source_encoding_node: "__ENCODING__", redo_node: "redo", retry_node: "retry",
        forwarding_arguments_node: "...", forwarding_parameter_node: "...", no_keywords_parameter_node: "**nil",
        it_local_variable_read_node: "it", implicit_rest_node: ""
      }.freeze
      TYPES = WORDS.keys.freeze

      def text = WORDS.fetch(type)
    end

    class Variable < Form
      TYPES = %i[
        instance_variable_read_node class_variable_read_node global_variable_read_node back_reference_read_node
        local_variable_target_node instance_variable_target_node class_variable_target_node
        global_variable_target_node constant_target_node constant_read_node required_parameter_node
        block_local_variable_node
      ].freeze

      def text = @node.name.to_s
    end

    class Reference < Form
      TYPES = %i[numbered_reference_read_node].freeze

      def text = "$#{@node.number}"
    end

    class Local < Form
      TYPES = %i[local_variable_read_node].freeze
      IMPLICIT = /\A_[1-9]\z/

      def text
        name = @node.name
        return name.to_s if @pen.local?(name) || name.match?(IMPLICIT)
        raise(Unbound, "kimera cannot write this read of #{name}: nothing binds the local there")
      end
    end

    class Numeral < Form
      TYPES = %i[integer_node float_node rational_node imaginary_node].freeze

      def text = Number.new(@node.value).text
    end

    class Atom < Form
      TYPES = %i[symbol_node].freeze

      def text = Name.new(@node.unescaped.to_sym).symbol
    end

    class Characters < Form
      TYPES = %i[string_node].freeze

      def text = %("#{Quote.new(@node.unescaped).text}")
    end

    class Command < Form
      TYPES = %i[x_string_node].freeze

      def text = "`#{Quote.new(@node.unescaped, "`").text}`"
    end

    class Path < Form
      TYPES = %i[constant_path_node constant_path_target_node].freeze

      def text
        parent = @node.parent
        parent ? "#{receiver_part(parent)}::#{@node.name}" : "::#{@node.name}"
      end
    end
  end
end
