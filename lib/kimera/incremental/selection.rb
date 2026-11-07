# frozen_string_literal: true

require_relative "extent"
require_relative "git_diff"

module Kimera
  module Incremental
  end
end

class Kimera::Incremental::Selection
  def self.from_diff(since:, root: ".", scope: "lines")
    extent = Kimera::Incremental::Extent.new(scope, root)
    new(extent.changes(Kimera::Incremental::GitDiff.new(since: since, root: root)), since, extent)
  end

  def initialize(changes, since, extent = Kimera::Incremental::Extent.new("lines"))
    @changes = changes
    @since = since
    @extent = extent
  end

  def ids(registry) = registry.each.filter_map { |mutant, point, file| mutant.to_i if touched?(point, file) }

  def files(found) = found.select { |file| @changes.key?(yield(file)) }

  def narrowed(registry) = registry.narrowed(@changes)

  def announce(io, selected, files)
    io.puts("Incremental: #{selected.size} mutants #{@extent.phrase(@since, files)}.")
  end

  private

  def touched?(point, file) = @changes.key?(file) && point.fits?(lines: @changes.fetch(file))
end
