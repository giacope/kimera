# frozen_string_literal: true

require_relative "ast_walk"

module Kimera
  module Rewrite
    module NumberedParams
      module_function

      PREFIX = "__kimera_"

      def normalize(node)
        AstWalk.rebuild(node) { |rebuilt, _original| dispatch(rebuilt) }
      end

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
        args = names.map { Parser::AST::Node.new(:arg, [it]) }
        args = [Parser::AST::Node.new(:procarg0, args)] if args.one?
        Parser::AST::Node.new(:args, args)
      end

      def rename(node, renames)
        AstWalk.rebuild(node) do |rebuilt, _original|
          name = rebuilt.type == :lvar ? rebuilt.children.first : nil
          renames.key?(name) ? rebuilt.updated(nil, [renames.fetch(name)]) : rebuilt
        end
      end
    end
  end
end
