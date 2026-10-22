# frozen_string_literal: true

require "parser"

module Kimera
  class Scribe
    # Builds nodes of the Parser AST, the tree Kimera::Scribe writes back as Ruby,
    # and the source buffer Kimera::Scribe reads them from.
    module Nodes
      private

      def ast(type, *children) = Parser::AST::Node.new(type, children)

      def buffer(source) = Parser::Source::Buffer.new("(kimera)", source: source)
    end
  end
end
