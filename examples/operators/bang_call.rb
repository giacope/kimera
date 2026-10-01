# frozen_string_literal: true

module MyApp
  module Operators
    # Strips the bang: `create!` becomes `create`, so a failed write returns
    # false instead of raising.
    #
    # A survivor means nothing exercises the failure path: the validation meant
    # to abort the request is never asserted.
    class BangCall < Kimera::Operators::Base
      NAMES = %i[save! update! create! destroy! find_by! reload!].freeze

      def key = "bang_call"

      def variants(node, **)
        return unless matches?(node, NAMES) && node.receiver
        to = node.name.to_s.chomp("!")
        solo("#{node.name} => #{to}", "selector_swap", to: to)
      end
    end
  end
end
