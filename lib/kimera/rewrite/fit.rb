# frozen_string_literal: true

require_relative "directive"

module Kimera
  module Rewrite
    class Fit
      def initialize(directive)
        @directive = directive
      end

      def applied(node)
        Kimera::Rewrite::Directive.new(@directive).apply(node)
      rescue StandardError
        yield
      end
    end
  end
end
