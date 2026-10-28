# frozen_string_literal: true

require_relative "git_diff"

module Kimera
  module Incremental
  end
end

class Kimera::Incremental::Selection
  def self.from_diff(since:, root: ".") = new(Kimera::Incremental::GitDiff.new(since: since, root: root).lines, since)

  def initialize(changes, since)
    @changes = changes
    @since = since
  end

  def ids(registry) = registry.points.flat_map { |point| touched(point) }

  def files(found) = found.select { |file| @changes.key?(yield(file)) }

  def narrowed(registry) = registry.narrowed(@changes)

  def announce(io, selected, files)
    io.puts("Incremental: #{selected.size} mutants on lines changed since #{@since} (#{files} changed files).")
  end

  private

  def touched(point)
    lines = @changes[point.file]
    return [] unless lines && point.location.range.any? { |line| lines.include?(line) }
    point.ids
  end
end
