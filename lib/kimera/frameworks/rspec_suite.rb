# frozen_string_literal: true

require "json"
require "rspec/core"
require_relative "suite"
require_relative "group_scope"
require_relative "group_tree"
require_relative "dot_rspec"
require_relative "../exits/test_exit"

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::RSpecSuite < Kimera::Frameworks::Suite
  class << self
    def build(settings = Kimera::Frameworks::DotRspec.new) = settings.configure(RSpec.configuration).then { new }
  end

  def initialize
    super
    @suites = Set.new
  end

  def source(files)
    preload
    each_test_file(files) { |file| load(file) }
    examples
    self
  end

  def test_ids
    examples.keys
  end

  def hooks = Hooks.new(@suites)

  def [](*ids) = Selection.new(ids, examples)

  def run(ids)
    selected = ids.filter_map { |id| examples[id] }
    reseed(ids.first)
    reset
    clear(selected)
    execute(selected)
    outcome(selected.select { |ex| ex.execution_result.status == :failed }.map { |ex| [ex.id, failure(ex)] })
  end

  private

  def preload(settings = Kimera::Frameworks::DotRspec.new) = settings.preload(RSpec.configuration)

  def failure(example)
    exception = example.execution_result.exception
    exception && ["#{exception.class}: #{exception.message}", *frames(filtered(exception))].join("\n    ")
  end

  def filtered(exception)
    RSpec.configuration.backtrace_formatter.format_backtrace(Array(exception.backtrace))
  end

  def reset
    world = RSpec.world
    world.wants_to_quit = false
    world.non_example_failure = false
  end

  def load(file) = Kernel.load(File.expand_path(file))

  def examples
    @_examples ||= selected.to_h { |example| [example.id, example.extend(Kimera::TestExit::Example)] }
  end

  def selected
    world = RSpec.world
    found = world.example_groups.flat_map { |top| Kimera::Frameworks::GroupTree.new(top).examples }
    return found unless found.empty? && RSpec.configuration.run_all_when_everything_filtered?
    return found if world.inclusion_filter.empty?
    world.inclusion_filter.clear
    selected
  end

  def clear(examples)
    examples.each { |ex| ex.instance_variable_set(:@exception, nil) }
  end

  def execute(selected)
    reporter = RSpec::Core::Reporter.new(RSpec.configuration)
    world = RSpec.world
    index = Kimera::Frameworks::GroupScope.new(selected, world)
    index.narrow { index.tops.each { |top| top.run(reporter) } }
  end
end

require_relative "rspec_suite/hooks"
require_relative "rspec_suite/selection"
