# frozen_string_literal: true

require_relative "ast_walk"

module Kimera
  module Rewrite
    module Conditions
      TESTS = %i[if while until while_post until_post].freeze
      NEGATION = [:!].freeze
      PASSAGES = %i[and or].freeze
      ENCLOSURES = %i[begin kwbegin].freeze
      READ_AS_CONDITIONS = %i[irange erange regexp].freeze

      module_function

      def places(root, tested: false)
        found = {}.compare_by_identity.merge!(root => tested)
        AstWalk.visit(root) { |node| mark(found, node) }
        found
      end

      def misread?(tree, tested:) = places(tree, tested: tested).any? { |node, test| test && literal?(node) }

      def literal?(node) = READ_AS_CONDITIONS.include?(node.type)

      def mark(found, node)
        children = node.children
        found[children.first] = true if tests?(node)
        children.each { found[it] = true } if found[node] && passes?(node)
      end

      def tests?(node)
        type = node.type
        TESTS.include?(type) || (type == :send && node.children.drop(1) == NEGATION)
      end

      def passes?(node)
        type = node.type
        PASSAGES.include?(type) || (ENCLOSURES.include?(type) && node.children.one?)
      end
    end
  end
end
