# frozen_string_literal: true

require_relative "ast_walk"
require_relative "../unparsing/unparse_nodes"

module Kimera
  module Rewrite
    class NumberedParams
      include Kimera::Unparse::Nodes

      PREFIX = "__kimera_"

      def initialize(tree)
        @tree = tree
      end

      def normalize
        AstWalk.new(@tree).rebuild { |rebuilt, _original| dispatch(rebuilt) }
      end

      private

      def dispatch(node)
        case node.type
        when :numblock then numbered(node)
        when :itblock then implicit(node)
        else node
        end
      end

      def numbered(node)
        call, count, body = node.children
        renames = (1..count).to_h { |n| [:"_#{n}", :"#{PREFIX}#{n}"] }
        node.updated(:block, [call, arguments(renames.values), rename(body, renames)])
      end

      def implicit(node)
        call, _name, body = node.children
        name = :"#{PREFIX}it"
        node.updated(:block, [call, arguments([name]), rename(body, { it: name })])
      end

      def arguments(names)
        parameters = names.map { ast(:arg, it) }
        parameters = [ast(:procarg0, *parameters)] if parameters.one?
        ast(:args, *parameters)
      end

      def rename(node, renames)
        AstWalk.new(node).rebuild do |rebuilt, _original|
          name = rebuilt.type == :lvar ? rebuilt.children.first : nil
          renames.key?(name) ? rebuilt.updated(nil, [renames.fetch(name)]) : rebuilt
        end
      end
    end
  end
end
