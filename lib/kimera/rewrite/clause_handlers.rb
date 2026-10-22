# frozen_string_literal: true

require_relative "../scribe/nodes"

module Kimera
  module Rewrite
    module ClauseHandlers
      DEFINITIONS = %i[def defs].freeze

      Operation =
        Data.define(:node, :directive) do
          include Kimera::Scribe::Nodes
          def rescued = rebody { |body| unrescued(body) }

          def ensured = rebody { |body| body.children[0] }

          def privatize
            ast(:begin, node, ast(:send, nil, :private, ast(:sym, node.children[0])))
          end

          def value = node.children.last

          def object
            built = ast(:send, ast(:const, ast(:cbase), :Object), :new)
            node.type == :nil ? built : node.updated(nil, [built])
          end

          def pattern
            source = directive["source"].to_s
            text = source.empty? ? [] : [ast(:str, source)]
            node.updated(nil, [*text, node.children.last])
          end
          private
          def rebody(&)
            type = node.type
            return redefined(&) if DEFINITIONS.include?(type)
            return node.updated(nil, node.children.filter_map(&)) if type == :kwbegin
            yield(node)
          end

          def redefined
            *head, body = node.children
            node.updated(nil, [*head, yield(body)])
          end

          def unrescued(body)
            case body&.type
            when :ensure then body.updated(nil, [unrescued(body.children[0]), body.children[1]])
            when :rescue then dropped(body)
            else body
            end
          end

          def dropped(handler)
            guarded, *clauses, otherwise = handler.children
            clauses.delete_at(Integer(directive[INDEX]))
            return handler.updated(nil, [guarded, *clauses, otherwise]) unless clauses.empty?
            parts = [guarded, otherwise].compact
            parts.one? ? parts.first : ast(:begin, *parts)
          end
        end
    end
  end
end
