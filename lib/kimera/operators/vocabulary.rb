# frozen_string_literal: true

require_relative "../support/syntax"

module Kimera
  module Operators
    Kimera::SyntaxTypes::Installer.new(self).call
    TYPE = "type"
    INDEX = "index"
    STATEMENT_DELETION = "statement_deletion"

    IDENTIFIER = /\A[A-Za-z_]\w*[!?]?\z/

    Variant = Struct.new(:label, :directive, keyword_init: true)

    CallQuery =
      Data.define(:node) do
        def named?(names)
          name = node.name
          names.is_a?(Symbol) ? name == names : names.include?(name)
        end

        def call?(names) = node.is_a?(SyntaxTypes::CallNode) && named?(names)
        def chained?(names) = call?(names) && !!node.receiver
        def bare?(names) = call?(names) && !node.receiver
      end

    module Vocabulary
      module_function

      def directive(type, **fields)
        { TYPE => type }.merge(fields.transform_keys(&:to_s))
      end

      def solo(label, type, **fields)
        [Variant.new(label: label, directive: directive(type, **fields))]
      end

      def deletion(node)
        solo("delete `#{first(node)}`", STATEMENT_DELETION)
      end

      def drops(nodes, type, label:)
        nodes.each_index.filter_map do |index|
          next if repeat?(nodes, index)
          Variant.new(label: "#{label} `#{first(nodes[index])}`", directive: directive(type, index: index))
        end
      end

      def repeat?(nodes, index) = index.positive? && nodes[index - 1] === nodes[index]

      def call(node) = CallQuery.new(node)

      { matches?: :call?, chained?: :chained?, bare?: :bare? }.each do |name, query|
        define_method(name) { |node, names| call(node).public_send(query, names) }
      end

      def identifier?(node)
        node.is_a?(SyntaxTypes::CallNode) && node.name.to_s.match?(IDENTIFIER)
      end

      def arguments(node)
        node.arguments&.arguments || []
      end

      def unary?(node)
        return false if node.block
        argument, extra = arguments(node)
        !extra && argument.is_a?(SyntaxTypes::Node) && !argument.is_a?(SyntaxTypes::SplatNode)
      end

      def keywords(node)
        arguments(node).reverse_each.find { |a| a.is_a?(SyntaxTypes::KeywordHashNode) }
      end

      def unescaped(node)
        node.unescaped if node.is_a?(SyntaxTypes::SymbolNode)
      end

      def first(node)
        node.location.slice.lines.first.to_s.strip
      end
    end
  end
end
