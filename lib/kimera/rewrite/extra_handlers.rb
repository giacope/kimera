# frozen_string_literal: true

require_relative "../scribe/nodes"

module Kimera
  module Rewrite
    module ExtraHandlers
      REQUIRED = { optional_parameter_node: :requireds, optional_keyword_parameter_node: :keywords }.freeze

      Operation =
        Data.define(:node, :directive) do
          include Kimera::Scribe::Nodes
          def trim(pair)
            value = pair.value
            position = Integer(directive[INDEX])
            pair.copy(value: value.copy(elements: value.elements.reject.with_index { |_, index| index == position }))
          end

          def default
            parameters = snippet("def kimera(required, keyword:) = nil").parameters
            parameters.public_send(REQUIRED.fetch(node.type)).first.copy(name: node.name)
          end

          def regexp = pattern(directive["source"].to_s, node.closing[1..])
        end
    end
  end
end
