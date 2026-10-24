# frozen_string_literal: true

require_relative "../scribe/nodes"

module Kimera
  module Rewrite
    module ClauseHandlers
      Operation =
        Data.define(:node, :directive) do
          include Kimera::Scribe::Nodes
          def rescued = node.type == :rescue_modifier_node ? node.expression : rebegun { |begun| unrescued(begun) }

          def ensured = rebegun { |begun| settled(begun.copy(ensure_clause: nil)) }

          def privatize = statements([node, snippet("private(:#{node.name})")])

          def value = node.value

          def object
            return snippet("::Object.new") if node.type == :nil_node
            node.copy(arguments: snippet("return ::Object.new").arguments)
          end

          def pattern = ExtraHandlers::Operation.new(node, directive).regexp

          def unbranched
            dropped = Integer(directive[INDEX])
            node.copy(conditions: node.conditions.reject.with_index { |_clause, at| at == dropped })
          end
          private
          def rebegun = node.type == :def_node ? node.copy(body: yield(node.body)) : yield(node)

          def unrescued(begun)
            clauses = Kimera::Syntax::RESCUES.call(begun.rescue_clause)
            clauses.delete_at(Integer(directive[INDEX]))
            clauses.empty? ? folded(begun) : begun.copy(rescue_clause: linked(clauses))
          end

          def linked(clauses) = clauses.reverse.reduce(nil) { |rest, clause| clause.copy(subsequent: rest) }

          def folded(begun)
            body = [*begun.statements&.body, *begun.else_clause&.statements&.body]
            settled(begun.copy(rescue_clause: nil, else_clause: nil, statements: statements(body)))
          end

          def settled(begun) = begun.rescue_clause || begun.ensure_clause ? begun : begun.statements
        end
    end
  end
end
