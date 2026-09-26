# frozen_string_literal: true

require "rspec/core"
require_relative "adapter"
require_relative "rspec_group_index"

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::RSpecAdapter < Kimera::Frameworks::Adapter
  class << self
    def build
      configure
      new
    end

    private

    def configure
      RSpec::Core::ConfigurationOptions.new([]).configure(RSpec.configuration)
    rescue StandardError, ScriptError
      nil
    end
  end

  def initialize
    super
    @examples = {}
    @suite = nil
  end

  def source(files)
    each_test_file(files) { |file| load(file) }
    reindex
    self
  end

  def test_ids
    @examples.keys
  end

  def describe(id)
    ex = @examples[id]
    ex ? ex.full_description : id
  end

  def start
    pid = Process.pid
    return if @suite == pid
    @suite = pid
    hooks(:@before_suite_hooks)
  end

  def finish
    return unless @suite == Process.pid
    hooks(:@after_suite_hooks)
  end

  def run(ids)
    selected = ids.filter_map { |id| @examples[id] }
    reset
    clear(selected)
    execute(selected)
    outcome(selected)
  end

  private

  def outcome(selected)
    failed = selected.select { |ex| ex.execution_result.status == :failed }
    Kimera::Frameworks::RunOutcome.new(
      passed: failed.empty?, failed_ids: failed.map(&:id),
      failures: failed.to_h { |example| [example.id, failure(example)] }
    )
  end

  def hooks(store)
    config = RSpec.configuration
    context = RSpec::Core::SuiteHookContext.new(store.to_s, config.reporter)
    config.instance_variable_get(store).each { |hook| hook.run(context) }
  end

  def failure(example)
    exception = example.execution_result.exception
    exception && "#{exception.class}: #{exception.message}"
  end

  def reset
    world = RSpec.world
    world.wants_to_quit = false
    world.non_example_failure = false
  end

  def load(file) = Kernel.load(File.expand_path(file))

  def reindex
    @examples = {}
    RSpec.world.example_groups.each { |top| index(top) }
  end

  def index(top)
    Kimera::Frameworks::RSpecGroupIndex.examples(top).each { |example| @examples[example.id] = example }
  end

  def clear(examples)
    examples.each { |ex| ex.instance_variable_set(:@exception, nil) }
  end

  def execute(selected)
    reporter = RSpec::Core::Reporter.new(RSpec.configuration)
    filtered = RSpec.world.filtered_examples
    wanted = selected.to_a
    Kimera::Frameworks::RSpecGroupIndex.top(selected).each { |top| perform(top, reporter, filtered, wanted) }
  end

  def perform(top, reporter, filtered, wanted)
    Kimera::Frameworks::RSpecGroupIndex.narrow(filtered, top, wanted) { top.run(reporter) }
  end
end

Kimera::Frameworks::Adapter.register(:rspec, Kimera::Frameworks::RSpecAdapter)
