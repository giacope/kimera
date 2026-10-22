# frozen_string_literal: true

module Kimera
  class Scribe
    class Assignment < Form
      TYPES = %i[
        local_variable_write_node instance_variable_write_node class_variable_write_node
        global_variable_write_node constant_write_node constant_path_write_node
      ].freeze

      def text
        value = @node.value
        target = type == :constant_path_write_node ? part(@node.target) : @node.name.to_s
        own = type == :local_variable_write_node ? Set[@node.name] : Binders::NONE
        "#{target} = #{pen_of(value).bound(own).write(value, value_floor(value))}"
      end

      def level = Level::ASSIGNMENT
    end

    class Compound < Form
      TYPES = %i[
        local_variable_operator_write_node local_variable_or_write_node local_variable_and_write_node
        instance_variable_operator_write_node instance_variable_or_write_node instance_variable_and_write_node
        class_variable_operator_write_node class_variable_or_write_node class_variable_and_write_node
        global_variable_operator_write_node global_variable_or_write_node global_variable_and_write_node
        constant_operator_write_node constant_or_write_node constant_and_write_node
        constant_path_operator_write_node constant_path_or_write_node constant_path_and_write_node
        call_operator_write_node call_or_write_node call_and_write_node
        index_operator_write_node index_or_write_node index_and_write_node
      ].freeze

      def text
        value = @node.value
        "#{target} #{operator}= #{pen_of(value).bound(Set[*own]).write(value, value_floor(value))}"
      end

      def level = Level::ASSIGNMENT

      private

      def own = type.start_with?("local_") ? [@node.name] : []

      def operator
        return @node.binary_operator.to_s if type.end_with?("operator_write_node")
        type.end_with?("or_write_node") ? "||" : "&&"
      end

      def target
        case type
        when /\Acall_/ then "#{receiver_part(@node.receiver)}#{@node.safe_navigation? ? "&." : "."}#{@node.read_name}"
        when /\Aindex_/ then "#{receiver_part(@node.receiver)}[#{listed(arguments)}]"
        when /\Aconstant_path_/ then part(@node.target)
        else @node.name.to_s
        end
      end

      def arguments = [*@node.arguments&.arguments, @node.block].compact
    end

    class Targets < Form
      TYPES = %i[multi_target_node].freeze

      def text = "(#{items})"

      def items = trailed([*@node.lefts, *@node.rest, *@node.rights])
    end

    class Multiple < Form
      TYPES = %i[multi_write_node].freeze

      def text = "#{Targets.new(@node, @pen).items} = #{part(@node.value, value_floor(@node.value))}"

      def level = Level::STATEMENT
    end

    class Attribute < Form
      TYPES = %i[call_target_node index_target_node].freeze

      def text
        receiver = receiver_part(@node.receiver)
        if type == :index_target_node
          return "#{receiver}[#{listed([*@node.arguments&.arguments, @node.block].compact)}]"
        end
        "#{receiver}#{@node.safe_navigation? ? "&." : "."}#{@node.name.to_s.delete_suffix("=")}"
      end
    end
  end
end
