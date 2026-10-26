# frozen_string_literal: true

module Kimera
  FactoryBlock =
    Data.define(:block) do
      def defining?
        body = block.body if block&.type == :block_node && block.parameters.nil?
        body&.type == :statements_node && body.body.any? { |statement| statement.type == :def_node }
      end
    end

  module GuardrailFactories
    FACTORIES = [%i[Struct new], %i[Data define], %i[Class new], %i[Module new]].freeze
    WRITES = %i[constant_write_node constant_path_write_node].freeze
    CONSTANTS = %i[constant_read_node constant_path_node].freeze
    LEXICAL = "(is_a?(::Module) ? self : ::Object)"

    private

    def reopen(node) = reopenable?(node) ? reopened(node, node.value) : node

    def reopenable?(node)
      return false unless WRITES.include?(node.type)
      value = node.value
      value.type == :call_node && value.block&.type == :block_node && factory?(value)
    end

    def factory?(call)
      receiver = call.receiver
      return false unless CONSTANTS.include?(receiver&.type) && !call.safe_navigation?
      FACTORIES.include?([receiver.name, call.name]) || Kimera::FactoryBlock.new(call.block).defining?
    end

    def reopened(node, value)
      constant = node.type == :constant_write_node ? snippet("Kimera").copy(name: node.name) : node.target
      evaluated = snippet("nil.class_eval do\nend").copy(receiver: constant)
      statements(
        [
          node.copy(value: existing(node, value.copy(block: nil))),
          evaluated.copy(block: evaluated.block.copy(body: value.block.body))
        ]
      )
    end

    def existing(node, factory)
      name = node.type == :constant_write_node ? node.name : node.target.name
      base = grouped([owner(node)])
      probe = snippet("nil.const_defined?(:#{name}, false)").copy(receiver: base)
      branched(probe, snippet("nil.const_get(:#{name})").copy(receiver: base), factory)
    end

    def owner(node)
      return snippet(LEXICAL).body.body.first if node.type == :constant_write_node
      node.target.parent || snippet("::Object")
    end
  end
end
