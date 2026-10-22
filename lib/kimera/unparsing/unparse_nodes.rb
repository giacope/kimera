# frozen_string_literal: true

require "parser"

module Kimera
  class Unparse
    # Builds nodes of the Parser AST, the tree unparser writes back as Ruby.
    module Nodes
      private

      def ast(type, *children) = Parser::AST::Node.new(type, children)
    end
  end
end
