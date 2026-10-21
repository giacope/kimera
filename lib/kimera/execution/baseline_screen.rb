# frozen_string_literal: true

require "tmpdir"
require_relative "baseline_failure"
require_relative "baseline_exclusions"
require_relative "failure_listing"
require_relative "suite_capture"
require_relative "suite_env"

# A test that fails in kimera's baseline has no trustworthy coverage, so
# kimera cannot say it covers no in-scope mutant. It reruns those tests in a
# plain process: one that passes there failed only under kimera, a harness
# error that stops the run; only tests that fail plainly too are excluded.
class Kimera::Execution::BaselineScreen
  CAUSES = {
    parallel: "they ran in workers forked from the one process that loaded the suite: state the suite sets up " \
      "once per process (a before(:suite) hook, a connection, a directory or port the workers share) differs " \
      "there; compare with --jobs 1",
    serial: "something kimera changes fails them: the forked worker, the instrumented code (a Ractor cannot " \
      "reach it), or the order tests run in; run the command above, then `kimera run --jobs 1` on their file"
  }.freeze

  def initialize(adapter:, root:, jobs:, suite: Kimera::Execution::SUITE)
    @adapter = adapter
    @root = root
    @jobs = jobs
    @suite = suite
  end

  def call(failures)
    return if failures.empty?
    ids = failures.keys
    passed = ids - rerun(ids)
    command = @adapter.reproduce(ids)
    raise(Kimera::Execution::BaselineFailure, harness(passed, failures, command)) unless passed.empty?
    Kimera::Execution::BaselineExclusions.new(failures, command).to_s
  end

  private

  def rerun(ids)
    Dir.mktmpdir("kimera-plain") do |dir|
      out = File.join(dir, "plain.json")
      argv = @adapter.plain(ids, out)
      return ids if argv.empty?
      output, status = @suite.call(Kimera::Execution::SUITE_ENV, *argv, chdir: @root)
      status.success? ? [] : failing(ids, output, out)
    end
  rescue SystemCallError
    ids
  end

  def failing(ids, output, out)
    named = @adapter.failed_plainly(output, out) & ids
    named.empty? ? ids : named
  end

  def harness(passed, failures, command)
    [
      "harness error: #{passed.size} test(s) fail under kimera but pass in a plain run, so kimera stops " \
        "rather than guess what they cover:",
      *Kimera::Execution::FailureListing.new(failures.slice(*passed)).lines,
      "  plain run: #{command}",
      "  likely cause: #{CAUSES.fetch(@jobs > 1 ? :parallel : :serial)}"
    ].join("\n")
  end
end
