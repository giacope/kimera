# frozen_string_literal: true

require_relative "../self_protection"
require_relative "isolated_child_command"
require_relative "isolated_kin"
require_relative "isolated_test_selection"
require_relative "pace"

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedPlan
  MIRROR_SKIP = %w[coverage].freeze
  MIRROR_EMPTY = %w[tmp log].freeze
  MIRROR_LINK = %w[vendor node_modules .bundle].freeze
  MIRROR_GIT = ".git"
  MIRROR_HINT =
    "  the mirror copies the project except #{MIRROR_SKIP.join(", ")} " \
      "(#{MIRROR_EMPTY.join(", ")} start empty; #{MIRROR_LINK.join(", ")} are symlinked; " \
      ".git is a private snapshot of the index and refs that reads the project's objects)".freeze

  attr_reader :registry

  def initialize(registry:, root:, tests:, **options)
    @registry = registry
    @given = root
    @tests = tests
    @options = options
  end

  def root = @_root ||= File.expand_path(@given)

  def tests(id, point, screened: true)
    file = point.file
    found = whole?(point) ? kin.tests(file) : selection.recorded(id)
    found = selection.all if Kimera::SelfProtection.new(File.join(root, file)).protected?
    screen = @options[:filter] if screened
    found && screen ? screen.keep(file, found) : found
  end

  def settled(id, point) = @options[:filter]&.settle(id, Array(tests(id, point, screened: false)))

  def command(mirror, locations, ledger, **)
    child.command(mirror, child.request(locations, **), ledger: ledger, paths: mutables)
  end

  def suite = selection.all

  def quality? = @options[:quality] == true

  def fastest(tests) = Kimera::Execution::Pace.new(timings).fastest(tests)

  def timings = @options.fetch(:timings, {})

  def mutables
    @registry.files.map { |f| f.split(File::SEPARATOR).first }.uniq
  end

  def placement(entry)
    return :copy if mutables.include?(entry)
    return :git if entry == MIRROR_GIT
    return :skip if MIRROR_SKIP.include?(entry)
    return :empty if MIRROR_EMPTY.include?(entry)
    MIRROR_LINK.include?(entry) ? :link : :copy
  end

  private

  def whole?(point)
    !point.safe? || point.revisit
  end

  def selection = @_selection ||= TestSelection.new(all_tests: @tests, coverage: @options.fetch(:coverage, {}))

  def kin
    @_kin ||= Kin.new(
      all: @tests, coverage: @options[:coverage] || {}, registry: @registry, locate: @options[:test_paths]
    )
  end

  def child
    @_child ||= ChildCommand.new(
      framework: @options.fetch(:framework), test_files: @options.fetch(:test_files), root: root, seed: @options[:seed]
    )
  end
end
