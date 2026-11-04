# frozen_string_literal: true

require_relative "../self_protection"
require_relative "baseline_failure"
require_relative "isolated_child_command"
require_relative "isolated_kin"
require_relative "isolated_test_selection"
require_relative "mirror_layout"

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedPlan
  def initialize(registry:, layout:, tests:, **options)
    @registry = registry
    @layout = layout
    @tests = tests
    @options = options
  end

  def tests(id, point)
    found = candidates(id, point)
    screen = @options[:filter]
    found && screen ? screen.keep(point.file, found) : found
  end

  def settled(id, point)
    Array(@options[:filter]).filter_map { |screen| screen.settle(id, Array(candidates(id, point))) }
  end

  def needed(ids)
    index = @registry.index
    @tests & ids.flat_map { |id| index.key?(id) ? Array(tests(id, index[id])) : [] }
  end

  def command(mirror, locations, ledger, **)
    request = child.request(locations, warnings: @options.fetch(:warnings, []), **)
    child.command(mirror, request, ledger: ledger, paths: @layout.mutables)
  end

  private

  def candidates(id, point)
    return if point.reasons(Kimera::Reason.unloaded).any?
    return @tests if everything?(point)
    whole?(point) ? kin.tests(point.file) : selection.recorded(id) { return }
  end

  def everything?(point, protection = Kimera::SelfProtection)
    point.reasons(Kimera::Reason.ordered).any? || protection.new(File.join(@layout.root, point.file)).protected?
  end

  def whole?(point)
    !point.safe? || point.reasons(Kimera::Reason.revisiting).any?
  end

  def selection = @_selection ||= @options.fetch(:selection) { selected }

  def selected = TestSelection.new(coverage: @options.fetch(:coverage, {}))

  def kin = @_kin ||= @options.fetch(:kin) { kindred }

  def kindred
    Kin.new(
      all: @tests, coverage: @options.fetch(:coverage, {}).to_h, registry: @registry,
      locate: @options[:test_paths] || ->(_test) { "" }
    )
  end

  def child = @_child ||= @options.fetch(:child) { commanded }

  def commanded
    ChildCommand.new(
      framework: @options.fetch(:framework), test_files: @options.fetch(:test_files), root: @layout.root,
      seed: @options[:seed]
    )
  end
end
