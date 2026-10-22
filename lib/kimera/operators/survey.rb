# frozen_string_literal: true

require_relative "vocabulary"

module Kimera
  module Operators
    module Survey
      def include?(node) = found.include?(node)

      private

      def found = @_found ||= Set.new.compare_by_identity.merge(nodes)
    end

    class EmptySurvey
      def include?(_node) = false
    end

    Survey::NONE = EmptySurvey.new
  end
end
