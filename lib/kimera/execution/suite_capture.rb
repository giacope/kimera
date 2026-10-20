# frozen_string_literal: true

require "tempfile"
require_relative "child_process"

class Kimera::Execution::SuiteCapture
  include Kimera::Execution::ChildProcess

  def call(env, *command, chdir:)
    Tempfile.create("kimera-suite") do |log|
      status = finished(Process.spawn(env, *command, chdir: chdir, in: File::NULL, out: log, err: log, pgroup: true))
      [File.read(log.path, encoding: Encoding::UTF_8).scrub, status]
    end
  end

  private

  def finished(pid) = Process.wait2(pid).last.tap { signal(-pid) }
end

Kimera::Execution::SUITE = Kimera::Execution::SuiteCapture.new
