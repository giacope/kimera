# frozen_string_literal: true

require "digest"
require_relative "suite_files"

module Kimera
  module Incremental
  end
end

class Kimera::Incremental::Stamp
  ROOTS = %w[.rspec Gemfile.lock].freeze

  def initialize(root:, sources:, settings:)
    @given = root
    @sources = sources
    @settings = settings
  end

  def to_s = Digest::SHA256.hexdigest([@settings.inspect, *entries].join("\n"))

  private

  def root = @_root ||= File.expand_path(@given)

  def entries
    read = @sources + ROOTS + Kimera::Incremental::SuiteFiles.new(@settings[:tests]).files(root)
    paths = read.map { |path| File.expand_path(path, root) }.uniq.sort
    paths.map { |path| "#{path.delete_prefix(root)}\0#{digest(path)}" }
  end

  def digest(path) = File.file?(path) ? Digest::SHA256.file(path).hexdigest : "-"
end
