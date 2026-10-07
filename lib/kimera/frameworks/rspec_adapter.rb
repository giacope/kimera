# frozen_string_literal: true

require "rspec/core"
require_relative "adapter"
require_relative "group_scope"
require_relative "group_tree"
require_relative "../support/test_exit"

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::RSpecAdapter < Kimera::Frameworks::Adapter
  class << self
    def build = new.configured
  end

  def initialize
    super
    @examples = {}
    @suite = nil
  end

  def configured
    configure
    self
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

  def locate(id) = { "location" => @examples.fetch(id).location.delete_prefix("./") }

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

  def configure
    RSpec::Core::ConfigurationOptions.new([]).configure(RSpec.configuration)
  rescue StandardError, ScriptError
    nil
  end

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

  def reindex
    @examples = {}
    RSpec.world.example_groups.each { |top| index(top) }
  end

  def index(top)
    Kimera::Frameworks::GroupTree.new(top).examples.each do |example|
      @examples[example.id] = example.extend(Kimera::TestExit::Example)
    end
  end

  def clear(examples)
    examples.each { |ex| ex.instance_variable_set(:@exception, nil) }
  end

  def execute(selected)
    reporter = RSpec::Core::Reporter.new(RSpec.configuration)
    index = Kimera::Frameworks::GroupScope.new(selected)
    index.narrow(RSpec.world.filtered_examples) { index.tops.each { |top| top.run(reporter) } }
  end
end

Kimera::Frameworks::ADAPTERS.register(:rspec, Kimera::Frameworks::RSpecAdapter)
