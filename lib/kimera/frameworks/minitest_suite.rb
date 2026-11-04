# frozen_string_literal: true

require_relative "suite"
require_relative "load_path"
require_relative "test_task"
require_relative "after_run"
require_relative "class_hooks"
require_relative "../exits/test_exit"

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::MinitestSuite < Kimera::Frameworks::Suite
  class << self
    def build(hooks = Hooks.new(Set.new))
      require("minitest")
      hooks.disarmed.then { new }
    end
  end

  def initialize(task: Kimera::Frameworks::TestTask.new, **)
    super(**)
    @loaders = Set.new
    @task = task
  end

  def source(files)
    @seed.given.each { |seed| Minitest.seed = seed }
    paths(files)
    @task.install
    each_test_file(files) { |file| require(file) }
    indexed
    @loaders.add?(Process.pid)
    self
  end

  def test_ids
    indexed.keys
  end

  def run(ids)
    outcome(ids.flat_map { |id| record(id) })
  end

  def hooks = Hooks.new(@loaders)

  def [](*ids) = Selection.new(ids, indexed, @task)

  private

  def record(id)
    klass, name = indexed[id]
    return [] unless klass
    result = Kimera::Frameworks::ClassHooks.new(klass).test(name) { reseed(id) }
    result && killing?(result) ? [[id, message(result)]] : []
  end

  def paths(files) = Kimera::Frameworks::LoadPath.new(files).install

  def indexed
    @_indexed ||= Minitest::Runnable.runnables.flat_map do |runnable|
      runnable.runnable_methods.map { |name| ["#{runnable}##{name}", [runnable, name]] }
    end.to_h
  end

  def killing?(result) = !result.passed? && !result.skipped?

  def message(result)
    assertion = result.failures.first
    assertion && [headline(assertion), *frames(Minitest.filter_backtrace(Array(assertion.backtrace)))].join("\n    ")
  end

  def headline(assertion)
    kind = assertion.class.name.split("::").last
    return "#{kind}: #{assertion.message}" unless assertion.is_a?(Minitest::UnexpectedError)
    error = assertion.error
    "#{kind}: #{error.class}: #{error.message}"
  end
end

require_relative "minitest_suite/hooks"
require_relative "minitest_suite/selection"
