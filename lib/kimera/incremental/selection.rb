# frozen_string_literal: true

require_relative "git_diff"

module Kimera
  module Incremental
    module Selection
      module_function

      def select(registry, changes)
        ids = []
        registry.points.each { |point| ids.concat(ids(point, changes)) }
        ids
      end

      def ids(point, changes)
        lines = changes[point.file]
        return [] unless lines && point.location.range.any? { |line| lines.include?(line) }
        point.ids
      end

      def changed(registry, since:, root: ".")
        select(registry, GitDiff.lines(since: since, root: root))
      end
    end
  end
end
