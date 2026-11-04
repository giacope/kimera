# frozen_string_literal: true

require "json"
require_relative "../runtime"
require_relative "../synthesis/body_trim"
require_relative "../synthesis/overlay"
require_relative "aliases"
require_relative "call_watch"
require_relative "child_process"
require_relative "overlay_guards"
require_relative "reload_errand"
require_relative "verdicts"

class Kimera::Execution::Reload
  include Kimera::Execution::ChildProcess

  LOADING = "the reload tier could not load the mutated source: "
  UNCALLED = "no test called the method that holds it"

  class Failure
    def initialize(exception)
      @exception = exception
    end

    def message = "#{exception.class}: #{exception.message}"

    def verdict = [:error, [], "#{LOADING}#{message}"]

    private

    attr_reader :exception
  end

  class Workspace
    def initialize(root:, aliases:)
      @root = root
      @aliases = aliases
    end

    def path(file) = File.join(File.expand_path(@root), file)

    def again(&) = (@aliases || Kimera::Execution::Aliases.new([])).again(&)
  end

  def initialize(registry:, adapter:, isolation:, workspace:)
    @registry = registry
    @adapter = adapter
    @isolation = isolation
    @workspace = workspace
  end

  def run(id, deadline:, tests: @adapter.test_ids)
    errand = Errand.new(id, tests, *IO.pipe(Encoding::UTF_8))
    collect(id, errand, child(id, errand), deadline)
  end

  private

  def child(id, errand)
    fork { work(id, errand) }.tap { errand.parent! }
  end

  def work(id, errand)
    lead
    errand.child!
    silence!
    errand.emit(report(id, errand))
    exit!(0)
  end

  def report(id, errand)
    started = monotonic
    status, fails, detail = evaluate(id, errand)
    errand.report(
      status: status.to_s, fails: Array(fails).map { |fail| fail.to_s.scrub }, detail: detail, ms: monotonic - started
    )
  end

  def monotonic(reading = Process.clock_gettime(Process::CLOCK_MONOTONIC)) = reading

  def collect(id, errand, pid, deadline)
    line = hear(errand, pid, deadline)
    verdict(id, line, bury(pid), deadline)
  end

  def hear(errand, pid, deadline)
    errand.await(deadline) { kill(pid) }
  rescue SignalException
    stop(pid)
    raise
  end

  def evaluate(id, errand)
    failed = mutate(id, errand)
    return failed.fetch(0).verdict unless failed.empty?
    errand.covered? ? [:survived, []] : [:no_coverage, [], UNCALLED]
  rescue Kimera::Overlay::Unbakeable => error
    [:unmutatable, [], verdicts.point(id).unmutatable(error.message)]
  rescue StandardError, ScriptError => error
    Failure.new(error).verdict
  end

  def mutate(id, errand)
    file = verdicts.point(id).file
    watch = overlay(file, @workspace.path(file), id)
    Kimera::RUNTIME.active = nil
    @isolation.around { hunt(errand, watch) }
  end

  def hunt(errand, watch)
    errand.failures { |test| trial(test, errand, watch) }
  end

  def trial(test, errand, watch)
    errand.tick(test)
    ledger = Kimera::RUNTIME.start!
    @adapter.run([test]).tap { errand.reach(test) if watch.reached?(Kimera::RUNTIME.stop!(ledger)) }
  end

  def overlay(file, path, id) = watched(file, path, id).tap { |watch| install(watch.source, path) }

  def watched(file, path, id, trims = Kimera::BodyTrim)
    location = verdicts.point(id).location
    source = trims.new(File.read(path, encoding: Encoding::UTF_8), [location]).trim(path)
    Kimera::Execution::CallWatch.new(Kimera::Overlay.new(@registry).bake(file, source, id), location.start_offset, id)
  end

  def install(source, path, guards = Kimera::Execution::OverlayGuards.new)
    @workspace.again { guards.overlay { Kimera::Overlay::Source.new(source).evaluate(path) } }
  end

  def verdict(id, line, status = nil, deadline = nil)
    return verdicts.timeout(id, deadline) if line == :timeout
    return verdicts.unjudged(id, "reload worker produced no result#{exited(status)}") unless line
    verdicts.parse(parse(line) { return verdicts.unjudged(id, "reload worker output unparseable") })
  end

  def exited(status)
    return "" unless status
    status.signaled? ? " (died on signal #{status.termsig})" : " (exited #{status.exitstatus})"
  end

  def verdicts
    Kimera::Execution::Verdicts.new(@registry)
  end
end
