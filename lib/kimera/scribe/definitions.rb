# frozen_string_literal: true

module Kimera
  class Scribe
    class Definition < Form
      TYPES = %i[def_node].freeze
      SIMPLE = %i[self_node local_variable_read_node instance_variable_read_node global_variable_read_node
        class_variable_read_node constant_read_node constant_path_node parentheses_node].freeze

      def text
        parameters = @node.parameters
        signature = parameters ? "(#{part(parameters)})" : ""
        "def #{receiver}#{@node.name}#{signature}#{clauses(@node.body, @scope.scoped([parameters]))}#{closing}"
      end

      def level = KEYWORD

      private

      def receiver
        owner = @node.receiver
        return "" unless owner
        bare = SIMPLE.include?(owner.type) || (owner.type == :call_node && owner.variable_call?)
        bare ? "#{part(owner, PRIMARY)}." : "(#{part(owner)})."
      end
    end

    class Namespace < Form
      TYPES = %i[class_node module_node singleton_class_node].freeze
      WORDS = { class_node: "class", module_node: "module", singleton_class_node: "class <<" }.freeze

      def text = "#{WORDS.fetch(type)} #{subject}#{parent}#{clauses(@node.body, @scope.scoped)}#{closing}"

      def level = KEYWORD

      private

      def subject = part(type == :singleton_class_node ? @node.expression : @node.constant_path, PRIMARY)

      def parent
        superclass = @node.superclass if type == :class_node
        superclass ? " < #{part(superclass, PRIMARY)}" : ""
      end
    end
  end
end
