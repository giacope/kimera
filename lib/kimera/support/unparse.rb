# frozen_string_literal: true

require_relative "warnings"

Kimera::Warnings.silence { require "unparser" }

module Kimera
  module Unparse
    module_function

    def parse(source) = Kimera::Warnings.silence { Unparser.parse(source) }

    def unparse(node) = Kimera::Warnings.silence { Unparser.unparse(node) }

    module Binders
      private

      def enter(node)
        super
        Binders.names(node).each { |name| define(name) }
      end

      class << self
        def names(node)
          case node.type
          when :match_var, :blockarg then [node.children.first].compact
          when :match_with_lvasgn then captures(node.children.first)
          else []
          end
        end

        def captures(regexp)
          *parts, options = regexp.children
          flags = options.children.include?(:x) ? Regexp::EXTENDED : 0
          Regexp.new(parts.sum("") { |part| part.children.first }, flags).names.map(&:to_sym)
        end
      end
    end

    module RangeEndpoints
      private

      def visit_begin_node(node) = endpoint(node) { super }

      def visit_end_node(node) = endpoint(node) { super }

      def endpoint(node) = node && n_array?(node) ? parentheses { visit(node) } : yield
    end

    module Numerals
      TYPES = %i[int float rational complex].freeze
      CHAINS = %i[send csend index block numblock itblock].freeze
      SIGNS = %i[-@ +@].freeze

      class << self
        def rooted?(node) = CHAINS.include?(node.type) && leading?(node.children.first)

        def leading?(node) = node.is_a?(Parser::AST::Node) && (TYPES.include?(node.type) || rooted?(node))

        def negative?(node) = TYPES.include?(node.type) && Unparser.unparse(node).start_with?("-")
      end

      module Enclosure
        private

        def visit(node) = fused?(node) ? parentheses { super } : super
      end

      module Operand
        include Enclosure

        private

        def fused?(node) = SIGNS.include?(selector) && Numerals.rooted?(node)
      end

      module Exponentiation
        include Enclosure

        private

        def fused?(node) = node.equal?(receiver) && selector.equal?(:**) && Numerals.negative?(node)
      end
    end
  end
end

Unparser::AST::LocalVariableScopeEnumerator.prepend(Kimera::Unparse::Binders)
Unparser::Emitter::Range.prepend(Kimera::Unparse::RangeEndpoints)
Unparser::Writer::Send::Unary.prepend(Kimera::Unparse::Numerals::Operand)
Unparser::Writer::Send::Binary.prepend(Kimera::Unparse::Numerals::Exponentiation)
