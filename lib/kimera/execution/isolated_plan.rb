# frozen_string_literal: true

require_relative "../self_protection"
require_relative "isolated_child_command"
require_relative "isolated_test_selection"
require_relative "pace"

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
    found = whole?(point) ? selection.all : selection.recorded(id)
    screen = @options[:filter]
    found && screen ? screen.keep(point.file, found) : found
  end

  def settled(id, point) = @options[:filter]&.settle(id, whole?(point) ? selection.all : Array(selection.recorded(id)))

  def command(mirror, locations, ledger, first: false)
    child.command(mirror, child.request(locations, first: first), ledger: ledger, paths: mutables)
  end

  def suite = selection.all

  def quality? = @options[:quality] == true

  def fastest(tests) = Kimera::Execution::Pace.new(@options.fetch(:timings, {})).fastest(tests)

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

  def whole?(point)
    Kimera::SelfProtection.new(File.join(root, point.file)).protected? || !point.safe? || point.revisit
  end

  def selection = @_selection ||= TestSelection.new(all_tests: @tests, coverage: @options.fetch(:coverage, {}))

  def child
    @_child ||= ChildCommand.new(
      framework: @options.fetch(:framework), test_files: @options.fetch(:test_files), root: root, seed: @options[:seed]
    )
  end
end
