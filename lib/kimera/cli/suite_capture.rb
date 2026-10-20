# frozen_string_literal: true

require "tempfile"

class Kimera::CLI::SuiteCapture
  def call(env, *command, chdir:)
    Tempfile.create("kimera-suite") do |log|
      status = finished(Process.spawn(env, *command, chdir: chdir, in: File::NULL, out: log, err: log, pgroup: true))
      [File.read(log.path, encoding: Encoding::UTF_8).scrub, status]
    end
  end

  private

  def finished(pid) = Process.wait2(pid).last.tap { sweep(pid) }

  def sweep(group)
    Process.kill("KILL", -group)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end
end

Kimera::CLI::SUITE = Kimera::CLI::SuiteCapture.new
