# frozen_string_literal: true

module MyApp
  module Operators
    # Rounds to whole units instead of cents, and swaps floor for ceil.
    #
    # A survivor means money precision is untested: an invoice off by a cent,
    # or rounding the wrong way at the half, passes.
    class MoneyRounding < Kimera::Operators::Base
      SWAPS = { floor: :ceil, ceil: :floor }.freeze

      def key = "money_rounding"

      def variants(node, **)
        return unless node.is_a?(Prism::CallNode) && node.receiver
        return precision if rounded?(node)
        to = SWAPS[node.name]
        solo("#{node.name} => #{to}", "selector_swap", to: to.to_s) if to
      end

      private

      def rounded?(node)
        node.name == :round && arguments(node).length == 1
      end

      def precision
        solo("round: drop precision", "drop_argument", index: 0)
      end
    end
  end
end
