# frozen_string_literal: true

require_relative "warnings"
require_relative "unparse_grouping"

Kimera::Warnings.silence { require "unparser" }

module Kimera
  module Unparse
    module_function

    def parse(source) = Kimera::Warnings.silence { Unparser.parse(source) }

    def unparse(node)
      text = Kimera::Warnings.silence { Unparser.unparse(Grouping.call(node)) }
      text.valid_encoding? ? text : raise(EncodingError, "unparser wrote a literal's raw bytes, invalid in UTF-8")
    end

    module RawBytes
      def diagnostic(type, reason, *)
        super unless reason == :invalid_encoding
      end
    end

    module Parsing
      def parser = super.tap { it.builder.extend(RawBytes) }
    end

    module Binders
      private

      def enter(node)
        super
        Kimera::Unparse::Declaration.new(node).names.each { |name| define(name) }
      end
    end

    module RangeEndpoints
      private

      def visit_begin_node(node) = endpoint(node) { super }

      def visit_end_node(node) = endpoint(node) { super }

      def endpoint(node) = node && n_array?(node) ? visit(node) : yield
    end
  end
end

class Kimera::Unparse::Declaration
  def initialize(node)
    @node = node
  end

  def names
    case @node.type
    when :match_var, :blockarg then [@node.children.first].compact
    when :match_with_lvasgn then captures(@node.children.first)
    else []
    end
  end

  private

  def captures(regexp)
    *parts, options = regexp.children
    flags = options.children.include?(:x) ? Regexp::EXTENDED : 0
    Regexp.new(parts.sum("") { |part| part.children.first }, flags).names.map(&:to_sym)
  end
end

Unparser.singleton_class.prepend(Kimera::Unparse::Parsing)
Unparser::AST::LocalVariableScopeEnumerator.prepend(Kimera::Unparse::Binders)
Unparser::Emitter::Range.prepend(Kimera::Unparse::RangeEndpoints)
