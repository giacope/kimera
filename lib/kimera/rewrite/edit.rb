# frozen_string_literal: true

require_relative "../scribe/nodes"

module Kimera
  module Rewrite
    class Edit
      include Kimera::Scribe::Nodes

      def initialize(node, directive)
        @node = node
        @directive = directive
      end

      def call(handler, *) = __send__(handler, *)

      private

      attr_reader :node, :directive
    end
  end
end
