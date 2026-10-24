# frozen_string_literal: true

require_relative "ast_walk"
require_relative "../scribe/nodes"

module Kimera
  module Rewrite
    class NumberedParams
      include Kimera::Scribe::Nodes

      PREFIX = "__kimera_"
      SCOPES = %i[block_node lambda_node].freeze

      def initialize(tree)
        @tree = tree
      end

      def normalize
        AstWalk.new(@tree).rebuild { |rebuilt, _original| dispatch(rebuilt) }
      end

      private

      def dispatch(node)
        return node unless SCOPES.include?(node.type)
        case node.parameters&.type
        when :numbered_parameters_node then named(node, numbered(node.parameters.maximum))
        when :it_parameters_node then named(node, { it: :"#{PREFIX}it" })
        else node
        end
      end

      def numbered(count) = (1..count).to_h { |n| [:"_#{n}", :"#{PREFIX}#{n}"] }

      def named(node, renames)
        node.copy(parameters: parameters(renames.values), body: node.body && rename(node.body, renames))
      end

      def parameters(names)
        listed = snippet("kimera { |kimera| }").block.parameters
        required = listed.parameters.requireds.first
        listed.copy(parameters: listed.parameters.copy(requireds: names.map { |name| required.copy(name: name) }))
      end

      def rename(node, renames)
        AstWalk.new(node).rebuild { |rebuilt, _original| renamed(rebuilt, renames) }
      end

      def renamed(node, renames)
        case node.type
        when :local_variable_read_node then renames.key?(node.name) ? node.copy(name: renames.fetch(node.name)) : node
        when :it_local_variable_read_node then local(renames.fetch(:it)).copy(location: node.location)
        else node
        end
      end
    end
  end
end
