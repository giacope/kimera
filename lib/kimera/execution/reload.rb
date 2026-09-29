# frozen_string_literal: true

require "json"
require_relative "../runtime"
require_relative "../synthesis/body_trim"
require_relative "../synthesis/overlay"
require_relative "child_process"
require_relative "overlay_guards"
require_relative "reload_errand"
require_relative "verdicts"

class Kimera::Execution::Reload
  include Kimera::Execution::ChildProcess

  Failure =
    Data.define(:exception) do
      def message = "#{exception.class}: #{exception.message}"

      def verdict
        return [:error, [message]] unless exception.is_a?(Kimera::Overlay::Unbakeable)
        [:unmutatable, [], "#{Kimera::MutationPoint::UNMUTATABLE}#{exception.message}"]
      end
    end

  def initialize(registry:, adapter:, isolation:, root:)
    @registry = registry
    @adapter = adapter
    @isolation = isolation
    @root = root
  end

  def run(id, deadline:, tests: @adapter.test_ids)
    errand = Errand.new(id, tests, *IO.pipe)
    collect(errand, child(errand), deadline)
  end

  private

  def child(errand)
    fork { work(errand) }.tap { errand.parent! }
  end

  def work(errand)
    errand.child!
    silence!
    errand.emit(report(errand))
    exit!(0)
  end

  def report(errand)
    status, fails, detail = evaluate(errand)
    JSON.generate(
      id: errand.id, status: status.to_s, fails: Array(fails).map { |fail| fail.to_s.scrub }, detail: detail
    )
  end

  def collect(errand, pid, deadline)
    line = errand.await(deadline) { kill(pid) }
    verdict(errand.id, line, reap(pid), deadline)
  end

  def evaluate(errand)
    failed = mutate(errand)
    failed ? failed.verdict : [:survived, []]
  rescue StandardError, ScriptError => error
    Failure.new(error).verdict
  end

  def mutate(errand)
    id = errand.id
    file = verdicts.point(id).file
    overlay(file, File.join(File.expand_path(@root), file), id)
    Kimera::Runtime.active = nil
    @isolation.around { hunt(errand) }
  end

  def hunt(errand)
    errand.tests.lazy.map { |test| trial(test, errand) }.reject(&:passed?).first
  end

  def trial(test, errand)
    errand.tick
    @adapter.run([test])
  end

  def overlay(file, path, id)
    source = Kimera::BodyTrim.trim(path, File.read(path, encoding: Encoding::UTF_8), [verdicts.point(id).location])
    baked = Kimera::Overlay.new(@registry).bake(file, source, id)
    Kimera::Execution::OverlayGuards.overlay { Kimera::Overlay.evaluate(baked, path) }
  end

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
