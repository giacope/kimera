# frozen_string_literal: true

module MyApp
  module Operators
    # Deletes the authorization call.
    #
    # A survivor means the suite passes with authorization removed: no test
    # asserts the 403, and the check is load-bearing only in production.
    class Authorization < Kimera::Operators::Base
      NAMES = %i[authorize authorize! policy_scope verify_authorized require_login!].freeze

      def key = "authorization"

      def statement? = true

      def variants(node, **)
        return unless matches?(node, NAMES)
        deletion(node)
      end
    end
  end
end
