# frozen_string_literal: true

require_relative "../unparsing/unparse_nodes"
require_relative "extra_handlers"
require_relative "invocation"
require_relative "pinned_predicate"

module Kimera
  module Rewrite
    module DirectiveHandlers
      Operation =
        Data.define(:node, :directive) do
          include Kimera::Unparse::Nodes
          def target = directive["to"]&.to_sym

          def swap
            receiver, _selector, *arguments = node.children
            node.updated(:send, [receiver, target, *arguments])
          end

          def retype = node.updated(target, node.children)

          def literal
            node.updated(target, [])
          end

          def clear
            node.updated(:nil, [])
          end

          def receiver
            node.children[0]
          end

          def unlink
            Invocation.new(node).block do |call|
              receiver, *rest = call.children
              call.updated(nil, [receiver.children[0], *rest])
            end
          end

          def send
            Invocation.new(node).block { |call| call.updated(:send, call.children) }
          end

          def retest
            predicate, *rest = node.children
            node.updated(nil, [PinnedPredicate.new(predicate).to(ast(target)), *rest])
          end

          def integer
            node.updated(:int, [Integer(directive["value"])])
          end

          def float
            node.updated(:float, [Float(directive["value"])])
          end

          def string
            node.updated(:str, [String(directive["value"])])
          end

          def empty
            node.updated(nil, [])
          end

          def drop
            Invocation.new(node).block do |call|
              receiver, selector, *arguments = call.children
              arguments.delete_at(Integer(directive[INDEX]))
              call.updated(nil, [receiver, selector, *arguments])
            end
          end

          def nothing
            node.updated(nil, [ast(:nil)])
          end

          def select
            Invocation.new(node).block do |call|
              Invocation.new(call).select(target)
            end
          end

          def remove
            elements = node.children.dup
            elements.delete_at(Integer(directive[INDEX]))
            node.updated(nil, elements)
          end

          def assign
            target, _operator, value = node.children
            node.updated(nil, [target, self.target, value])
          end

          def keyword
            kwargs { |pair| extra.trim(pair) }
          end

          def option
            kwargs { |_pair| next }
          end

          def kwargs(&)
            Invocation.new(node).block { |call| Invocation.new(call).rewrite(directive["key"], &) }
          end

          def fetch
            extra.fetch
          end

          def argument
            extra.argument
          end

          def symbol
            extra.symbol
          end

          def default
            extra.default
          end

          def regexp
            extra.regexp
          end

          def extra
            ExtraHandlers::Operation.new(node, directive)
          end
        end
    end
  end
end
