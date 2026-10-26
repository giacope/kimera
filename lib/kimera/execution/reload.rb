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

  Failure =
    Data.define(:exception) do
      def message = "#{exception.class}: #{exception.message}"

      def verdict = [:error, [], "#{LOADING}#{message}"]
    end

  Workspace = Data.define(:root, :aliases)

  def initialize(registry:, adapter:, isolation:, workspace:)
    @registry = registry
    @adapter = adapter
    @isolation = isolation
    @workspace = workspace
  end

  def run(id, deadline:, tests: @adapter.test_ids)
    errand = Errand.new(id, tests, *IO.pipe(Encoding::UTF_8))
    collect(errand, child(errand), deadline)
  end

  private

  def child(errand)
    fork { work(errand) }.tap { errand.parent! }
  end

  def work(errand)
    lead
    errand.child!
    silence!
    errand.emit(report(errand))
    exit!(0)
  end

  def report(errand)
    started = monotonic
    status, fails, detail = evaluate(errand)
    JSON.generate(
      id: errand.id, status: status.to_s, fails: Array(fails).map { |fail| fail.to_s.scrub }, detail: detail,
      ms: monotonic - started, cover: errand.reached
    )
  end

  def monotonic(reading = Process.clock_gettime(Process::CLOCK_MONOTONIC)) = reading

  def collect(errand, pid, deadline)
    line = hear(errand, pid, deadline)
    verdict(errand.id, line, bury(pid), deadline)
  end

  def hear(errand, pid, deadline)
    errand.await(deadline) { kill(pid) }
  rescue SignalException
    stop(pid)
    raise
  end

  def evaluate(errand)
    failed = mutate(errand)
    return failed.verdict if failed
    errand.reached.empty? ? [:no_coverage, [], UNCALLED] : [:survived, []]
  rescue Kimera::Overlay::Unbakeable => error
    [:unmutatable, [], "#{Kimera::MutationPoint::UNMUTATABLE}#{error.message}"]
  rescue StandardError, ScriptError => error
    Failure.new(error).verdict
  end

  def mutate(errand)
    id = errand.id
    file = verdicts.point(id).file
    watch = overlay(file, File.join(File.expand_path(@workspace.root), file), id)
    Kimera::RUNTIME.active = nil
    @isolation.around { hunt(errand, watch) }
  end

  def hunt(errand, watch)
    errand.tests.lazy.map { |test| trial(test, errand, watch) }.reject(&:passed?).first
  end

  def trial(test, errand, watch)
    errand.tick(test)
    ledger = Kimera::RUNTIME.start!
    @adapter.run([test]).tap { errand.reach(test) if watch.reached?(Kimera::RUNTIME.stop!(ledger)) }
  end

  def overlay(file, path, id) = watched(file, path, id).tap { |watch| install(watch.source, path) }

  def watched(file, path, id)
    location = verdicts.point(id).location
    source = Kimera::BodyTrim.new(File.read(path, encoding: Encoding::UTF_8), [location]).trim(path)
    Kimera::Execution::CallWatch.new(Kimera::Overlay.new(@registry).bake(file, source, id), location.start_line, id)
  end

  def install(source, path)
    aliases.again { Kimera::Execution::OverlayGuards.new.overlay { Kimera::Overlay::Source.new(source).evaluate(path) } }
  end

  def aliases = @workspace.aliases || Kimera::Execution::Aliases.new([])

  def verdict(id, line, status = nil, deadline = nil)
    return verdicts.timeout(id, deadline) if line == :timeout
    return verdicts.unjudged(id, "reload worker produced no result#{exited(status)}") unless line
    message = parse(line)
    message ? verdicts.parse(message) : verdicts.unjudged(id, "reload worker output unparseable")
  end

  def exited(status)
    return "" unless status
    status.signaled? ? " (died on signal #{status.termsig})" : " (exited #{status.exitstatus})"
  end

  def verdicts
    Kimera::Execution::Verdicts.new(@registry)
  end
end
