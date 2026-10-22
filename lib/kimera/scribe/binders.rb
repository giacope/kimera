# frozen_string_literal: true

module Kimera
  class Scribe
    class Binders
      NAMED = %i[lvasgn arg optarg restarg kwarg kwoptarg kwrestarg blockarg shadowarg match_var].freeze
      OPENING = { block: 1, numblock: 1, itblock: 1, def: 0, defs: 1, class: 2, module: 1, sclass: 1 }.freeze
      NONE = Set.new.freeze

      def initialize
        @memo = {}.compare_by_identity
      end

      def of(node)
        return NONE unless node.is_a?(Parser::AST::Node)
        @memo[node] ||= declared(node).freeze
      end

      private

      def declared(node)
        name, value = node.children
        return Set.new([name].compact).merge(of(value)) if NAMED.include?(node.type)
        return Captures.new(name).names.merge(of(value)) if node.type == :match_with_lvasgn
        outer(node)
      end

      def outer(node)
        open = node.children.first(OPENING.fetch(node.type, node.children.size))
        open.reduce(Set.new) { |names, child| names.merge(of(child)) }
      end
    end

    class Captures
      def initialize(regexp)
        @regexp = regexp
      end

      def names
        *parts, options = @regexp.children
        return Set.new unless parts.all? { |part| part.type == :str }
        flags = options.children.include?(:x) ? Regexp::EXTENDED : 0
        Set.new(Regexp.new(parts.sum("") { |part| part.children.first }, flags).names.map(&:to_sym))
      rescue RegexpError
        Set.new
      end
    end
  end
end
