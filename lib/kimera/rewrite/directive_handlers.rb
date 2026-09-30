# frozen_string_literal: true

require_relative "directive_extra_handlers"
require_relative "directive_kwarg_handlers"

module Kimera
  module Rewrite
    module DirectiveHandlers
      Operation =
        Data.define(:node, :directive) do
          def target = directive["to"]&.to_sym

          def swap
            receiver, _selector, *args = node.children
            node.updated(:send, [receiver, target, *args])
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
            DirectiveKwargHandlers.block(node) do |call|
              receiver, *rest = call.children
              call.updated(nil, [receiver.children[0], *rest])
            end
          end

          def send
            DirectiveKwargHandlers.block(node) { |call| call.updated(:send, call.children) }
          end

          def retest
            node.updated(nil, [ast(target), *node.children[1..]])
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
            DirectiveKwargHandlers.block(node) do |call|
              receiver, selector, *args = call.children
              args.delete_at(Integer(directive[INDEX]))
              call.updated(nil, [receiver, selector, *args])
            end
          end

          def nothing
            node.updated(nil, [ast(:nil)])
          end

          def select
            DirectiveKwargHandlers.block(node) do |call|
              DirectiveKwargHandlers.select(call, target)
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
            DirectiveKwargHandlers.block(node) { |call| DirectiveKwargHandlers.rewrite(call, directive["key"], &) }
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
            DirectiveExtraHandlers::Operation.new(node, directive)
          end

          def ast(type, *children)
            Parser::AST::Node.new(type, children)
          end
        end
    end
  end
end
