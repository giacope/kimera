# frozen_string_literal: true

require_relative "../self_protection"
require_relative "isolated_child_command"
require_relative "isolated_test_selection"

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedPlan
  MIRROR_SKIP = %w[.git tmp vendor node_modules coverage log .bundle].freeze

  attr_reader :registry

  def initialize(registry:, root:, tests:, **options)
    @registry = registry
    @given = root
    @tests = tests
    @options = options
  end

  def root = @_root ||= File.expand_path(@given)

  def tests(id, point)
    all = selection.all
    return all if Kimera::SelfProtection.protected?(File.join(root, point.file))
    return all unless point.safe?
    selection.recorded(id)
  end

  def command(mirror, locations)
    child.command(mirror, locations, paths: mutables)
  end

  def mutables
    @registry.files.map { |f| f.split(File::SEPARATOR).first }.uniq
  end

  class << self
    def mirrors(entries)
      entries.reject { |entry| MIRROR_SKIP.include?(entry) }
    end
  end

  private

  def selection = @_selection ||= TestSelection.new(all_tests: @tests, coverage: @options.fetch(:coverage, {}))

  def child
    @_child ||= ChildCommand.new(framework: @options.fetch(:framework), test_files: @options.fetch(:test_files))
  end
end
