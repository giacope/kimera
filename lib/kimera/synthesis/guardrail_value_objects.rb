# frozen_string_literal: true

module Kimera
  module GuardrailValueObjects
    FACTORIES = [%i[Struct new], %i[Data define], %i[Class new], %i[Module new]].freeze

    private

    def reopen(node)
      return node unless node.type == :casgn
      scope, name, value = node.children
      return node unless type?(value, :block)
      block(node, scope, name, value)
    end

    def block(node, scope, name, value)
      factory, _arguments, body = value.children
      return node unless factory?(factory)
      reopened(node, scope, name, factory, body)
    end

    def reopened(node, scope, name, factory, body)
      ast(
        :begin,
        node.updated(nil, [scope, name, constant(ast(:begin, scope || context), ast(:sym, name), factory)]),
        ast(:block, ast(:send, ast(:const, scope, name), :class_eval), ast(:args), body)
      )
    end

    def constant(base, sym, factory)
      ast(:if, ast(:send, base, :const_defined?, sym, ast(:false)), ast(:send, base, :const_get, sym), factory)
    end

    def context
      identity = ast(:self)
      root = ast(:cbase)
      ast(:if, ast(:send, identity, :is_a?, ast(:const, root, :Module)), identity, ast(:const, root, :Object))
    end

    def factory?(call)
      return false unless type?(call, :send)
      receiver, selector = call.children
      type?(receiver, :const) && FACTORIES.include?([receiver.children[1], selector])
    end
  end
end
