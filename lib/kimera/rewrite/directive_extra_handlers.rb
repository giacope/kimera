# frozen_string_literal: true

module Kimera
  module Rewrite
    module DirectiveExtraHandlers
      Operation =
        Data.define(:node, :directive) do
          def trim(pair)
            key, value = pair.children
            elements = value.children.dup
            elements.delete_at(Integer(directive[INDEX]))
            pair.updated(nil, [key, value.updated(nil, elements)])
          end

          def fetch
            node.type == :index ? index(node) : call(node)
          end

          def index(node)
            receiver, *args = node.children
            node.updated(:send, [receiver, :fetch, *args])
          end

          def call(node)
            receiver, _selector, *args = node.children
            node.updated(nil, [receiver, :fetch, *args])
          end

          def argument
            node.children[2]
          end

          def symbol
            node.updated(:sym, [directive["value"].to_sym])
          end

          def default
            node.updated(node.type == :kwoptarg ? :kwarg : :arg, [node.children[0]])
          end

          def regexp
            source = directive["source"].to_s
            ast(:regexp, *(source.empty? ? [] : [ast(:str, source)]), ast(:regopt))
          end

          def ast(type, *children)
            Parser::AST::Node.new(type, children)
          end
        end
    end
  end
end
