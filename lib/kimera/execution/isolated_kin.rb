# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedPlan; end

class Kimera::Execution::IsolatedPlan::Kin
  CONVENTIONS = ["%s_spec.rb", "%s_test.rb", "test_%s.rb"].freeze

  def initialize(all:, coverage:, registry:, paths: {})
    @all = all
    @coverage = coverage
    @registry = registry
    @paths = paths
  end

  def tests(file)
    near = covering(file)
    return @all if near.empty?
    files = near | conventional(file)
    found = @all.select { |test| files.include?(path(test)) }
    found.empty? ? @all : found
  end

  private

  def covering(file)
    ids = @registry.at(file).select(&:safe?).flat_map(&:ids)
    ids.flat_map { |id| Array(@coverage[id] || @coverage[id.to_s]) }.map { |test| path(test) }.uniq - [""]
  end

  def conventional(file)
    names = CONVENTIONS.map { |shape| format(shape, File.basename(file, ".rb")) }
    @all.map { |test| path(test) }.uniq.select { |test| names.include?(File.basename(test)) }
  end

  def path(test) = @paths.fetch(test) { test[/\A(.+?)\[/, 1] }.to_s.delete_prefix("./")
end
