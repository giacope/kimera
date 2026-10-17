# frozen_string_literal: true

require_relative "git_diff"

module Kimera
  module Incremental
    class Selection
      def self.from_diff(since:, root: ".") = new(GitDiff.new(since: since, root: root).lines)

      def initialize(changes)
        @changes = changes
      end

      def ids(registry) = registry.points.flat_map { |point| touched(point) }

      private

      def touched(point)
        lines = @changes[point.file]
        return [] unless lines && point.location.range.any? { |line| lines.include?(line) }
        point.ids
      end
    end
  end
end
