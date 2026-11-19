# frozen_string_literal: true

require "json"
require_relative "../runtime"
require_relative "../synthesis/body_trim"
require_relative "../synthesis/overlay"
require_relative "aliases"
require_relative "call_watch"
require_relative "overlay_guards"
require_relative "verdicts"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Reload; end

class Kimera::Execution::Reload::Trial
  LOADING = "the reload tier could not load the mutated source: "
  UNCALLED = "no test called the method that holds it"

  class Failure
    def initialize(exception)
      @exception = exception
    end

    def verdict = [:error, [], "#{LOADING}#{@exception.class}: #{@exception.message}"]
  end

  def initialize(registry:, adapter:, isolation:, workspace:)
    @registry = registry
    @adapter = adapter
    @isolation = isolation
    @workspace = workspace
  end

  def report(id, errand)
    started = monotonic
    status, fails, detail = evaluate(id, errand)
    errand.report(
      status: status.to_s, fails: Array(fails).map { |fail| fail.to_s.scrub }, detail: detail, ms: monotonic - started
    )
  end

  def evaluate(id, errand)
    failed = mutate(id, errand)
    return failed.fetch(0).verdict unless failed.empty?
    errand.covered? ? [:survived, []] : [:no_coverage, [], UNCALLED]
  rescue Kimera::Overlay::Unbakeable => error
    [:unmutatable, [], Kimera::Reason.unmutatable(error.message).to_s]
  rescue StandardError, ScriptError => error
    Failure.new(error).verdict
  end

  private

  def monotonic(reading = Process.clock_gettime(Process::CLOCK_MONOTONIC)) = reading

  def mutate(id, errand, runtime = Kimera::RUNTIME)
    file = @registry[id].last
    watch = overlay(file, @workspace.path(file), id)
    runtime.during(nil) { @isolation.around { hunt(errand, watch) } }
  end

  def hunt(errand, watch)
    errand.failures { |test| trial(test, errand, watch) }
  end

  def trial(test, errand, watch, runtime = Kimera::RUNTIME)
    errand.tick(test)
    ledger = Kimera::Runtime::Ledger.new
    runtime.during(nil, ledger) { @adapter.run([test]) }.tap { errand.reach(test) if watch.reached?(ledger.drain!) }
  end

  def overlay(file, path, id) = watched(file, path, id).tap { |watch| install(watch.source, path) }

  def watched(file, path, id, trims = Kimera::BodyTrim)
    point = Kimera::Execution::Verdicts.new(@registry).point(id)
    source = trims.new(File.read(path, encoding: Encoding::UTF_8), [point]).trim(path)
    Kimera::Execution::CallWatch.new(Kimera::Overlay.new(@registry).bake(file, source, id), point, id)
  end

  def install(source, path, guards = Kimera::Execution::OverlayGuards.new)
    @workspace.again { guards.overlay { Kimera::Overlay::Source.new(source).evaluate(path) } }
  end
end
