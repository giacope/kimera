# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "baseline_failure"
require_relative "baseline_exclusions"
require_relative "captured_methods"
require_relative "failure_listing"
require_relative "suite_capture"

class Kimera::Execution::BaselineScreen
  CAUSES = {
    parallel: "they ran in workers forked from the one process that loaded the suite: state the suite sets up " \
      "once per process (a before(:suite) hook, a connection, a directory or port the workers share) differs " \
      "there; compare with --jobs 1",
    serial: "something kimera changes fails them: the forked worker, the instrumented code (a Ractor cannot " \
      "reach it), or the order tests run in; run the command above, then `kimera run --jobs 1` on their file"
  }.freeze

  def initialize(adapter:, root:, jobs:, suite: Kimera::Execution::SuiteCapture.new)
    @adapter = adapter
    @root = root
    @jobs = jobs
    @suite = suite
  end

  def call(failures)
    return if failures.empty?
    plainly!(failures)
    Kimera::Execution::BaselineExclusions.new(failures, @adapter[*failures.keys].to_s).to_s
  end

  def plainly!(failures)
    ids = failures.keys
    passed = ids - rerun(ids)
    raise(Kimera::Execution::BaselineFailure, harness(passed, failures, @adapter[*ids].to_s)) unless passed.empty?
  end

  private

  def rerun(ids, dirs = Dir)
    dirs.mktmpdir("kimera-plain") do |dir|
      out = File.join(dir, "plain.json")
      argv = @adapter[*ids].plain(out)
      return ids if argv.empty?
      output, status = @suite.call(*argv, chdir: @root)
      status.success? ? [] : failing(ids, output, out)
    end
  rescue SystemCallError, JSON::ParserError
    ids
  end

  def failing(ids, output, out)
    named = @adapter[*ids].failed(output, out) & ids
    named.empty? ? ids : named
  end

  def harness(passed, failures, command)
    [
      "harness error: #{passed.size} test(s) fail under kimera but pass in a plain run, so kimera stops " \
        "rather than guess what they cover:",
      *Kimera::Execution::FailureListing.new(failures.slice(*passed)).lines,
      "  plain run: #{command}",
      "  likely cause: #{cause}"
    ].join("\n")
  end

  def cause = Kimera::Execution::CapturedMethods.new(@root).cause || CAUSES.fetch(@jobs > 1 ? :parallel : :serial)
end
