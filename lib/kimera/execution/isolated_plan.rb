# frozen_string_literal: true

require_relative "../self_protection"
require_relative "isolated_child_command"
require_relative "isolated_test_selection"

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedPlan
  MIRROR_SKIP = %w[.git coverage].freeze
  MIRROR_EMPTY = %w[tmp log].freeze
  MIRROR_LINK = %w[vendor node_modules .bundle].freeze
  MIRROR_HINT =
    "  the mirror copies the project except #{MIRROR_SKIP.join(", ")} " \
      "(#{MIRROR_EMPTY.join(", ")} start empty; #{MIRROR_LINK.join(", ")} are symlinked)".freeze

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

  def command(mirror, locations, ledger)
    child.command(mirror, locations, ledger: ledger, paths: mutables)
  end

  def suite = selection.all

  def mutables
    @registry.files.map { |f| f.split(File::SEPARATOR).first }.uniq
  end

  def placement(entry)
    return :copy if mutables.include?(entry)
    return :skip if MIRROR_SKIP.include?(entry)
    return :empty if MIRROR_EMPTY.include?(entry)
    MIRROR_LINK.include?(entry) ? :link : :copy
  end

  private

  def selection = @_selection ||= TestSelection.new(all_tests: @tests, coverage: @options.fetch(:coverage, {}))

  def child
    @_child ||= ChildCommand.new(framework: @options.fetch(:framework), test_files: @options.fetch(:test_files))
  end
end
