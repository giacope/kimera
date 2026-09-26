# frozen_string_literal: true

require_relative "adapter"

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::MinitestAdapter < Kimera::Frameworks::Adapter
  TESTROOTS = %w[test spec].freeze
  INSTALLED = true

  class << self
    def build
      require("minitest")
      Minitest.seed ||= 1
      disable
      new
    end

    private

    def disable
      Minitest.class_variable_set(:@@installed_at_exit, INSTALLED)
    rescue NameError, ArgumentError
      Minitest.define_singleton_method(:run) { |*| true }
    end
  end

  def initialize
    super
    @methods = {}
  end

  def source(files)
    paths(files)
    Array(files).each { |f| load(File.expand_path(f)) }
    reindex
    self
  end

  def test_ids
    @methods.keys
  end

  def run(ids)
    failed = []
    failures = {}
    ids.each { |id| record(id, failed, failures) }
    Kimera::Frameworks::RunOutcome.new(passed: failed.empty?, failed_ids: failed, failures: failures)
  end

  private

  def record(id, failed, failures)
    klass, name = @methods[id]
    return unless klass
    result = klass.new(name).run
    return unless killing?(result)
    failure(id, result, failed, failures)
  end

  def failure(id, result, failed, failures)
    failed << id
    failures[id] = message(result)
  end

  def paths(files)
    Array(files).each do |file|
      parts = File.expand_path(file).split(File::SEPARATOR)
      TESTROOTS.each { |root| prepend(parts, root) }
    end
  end

  def prepend(parts, root)
    index = parts.rindex(root)
    return unless index
    dir = parts[0..index].join(File::SEPARATOR)
    $LOAD_PATH.unshift(dir) unless $LOAD_PATH.include?(dir)
  end

  def reindex
    @methods = {}
    Minitest::Runnable.runnables.each { |runnable| index(runnable) }
  end

  def index(runnable)
    runnable.runnable_methods.each { |name| @methods["#{runnable}##{name}"] = [runnable, name] }
  end

  def killing?(result)
    !result.passed? && !result.skipped?
  end

  def message(result)
    assertion = result.failures.first
    assertion && "#{assertion.class.name.split("::").last}: #{assertion.message}"
  end
end

Kimera::Frameworks::Adapter.register(:minitest, Kimera::Frameworks::MinitestAdapter)
