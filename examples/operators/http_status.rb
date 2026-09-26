# frozen_string_literal: true

module MyApp
  module Operators
    # Drops the `status:` keyword, so the response falls back to 200 OK.
    #
    # A survivor means the status code is untested: request specs assert the
    # body and let 201, 202 and 422 pass as 200.
    class HttpStatus < Kimera::Operators::Base
      NAMES = %i[render redirect_to head].freeze
      KEY = "status"

      class << self
        def key = "http_status"
      end

      def variants(node, **)
        return unless matches?(node, NAMES) && status?(node)
        solo("drop `status:`", "kwarg_pair_drop", key: KEY)
      end

      private

      def status?(node)
        keywords(node)&.elements.to_a.any? do |assoc|
          assoc.is_a?(Prism::AssocNode) && unescaped(assoc.key) == KEY
        end
      end
    end
  end
end
