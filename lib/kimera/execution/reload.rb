# frozen_string_literal: true

require "json"
require_relative "aliases"
require_relative "child_process"
require_relative "reload_errand"
require_relative "reload_trial"
require_relative "verdicts"

class Kimera::Execution::Reload
  include Kimera::Execution::ChildProcess

  class Workspace
    def initialize(root:, aliases:)
      @root = root
      @aliases = aliases
    end

    def path(file) = File.join(File.expand_path(@root), file)

    def again(&) = (@aliases || Kimera::Execution::Aliases.new([])).again(&)
  end

  def initialize(registry:, adapter:, trial:)
    @registry = registry
    @adapter = adapter
    @trial = trial
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
    silence!
    errand.emit(@trial.report(id, errand))
    exit!(0)
  end

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

  def verdict(id, line, status, deadline)
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
