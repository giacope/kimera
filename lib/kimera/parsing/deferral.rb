# frozen_string_literal: true

require_relative "syntax_types"

module Kimera
  class Deferral
    DEFINERS = %i[define_method define_singleton_method].freeze
    CALLABLES = %i[lambda proc].freeze

    def initialize(node)
      @node = node
    end

    def block
      return unless @node.is_a?(SyntaxTypes::CallNode) && callable?
      found = @node.block
      found if found.is_a?(SyntaxTypes::BlockNode)
    end

    def name
      return unless block && DEFINERS.include?(@node.name)
      named = @node.arguments&.arguments&.first
      named.unescaped if named.is_a?(SyntaxTypes::SymbolNode) || named.is_a?(SyntaxTypes::StringNode)
    end

    private

    def callable?
      name = @node.name
      return DEFINERS.include?(name) || (CALLABLES.include?(name) && !@node.receiver) unless name == :new
      receiver = @node.receiver
      receiver.is_a?(SyntaxTypes::ConstantReadNode) && receiver.name == :Proc
    end
  end
end
