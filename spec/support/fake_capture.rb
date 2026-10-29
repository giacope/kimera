# frozen_string_literal: true

# The test suite as Kimera::Execution::SuiteCapture runs it: each command
# answers what the block makes of it (by default an empty output and a
# successful exit), and the capture writes down each command with the
# directory and the time limit it ran under.
class FakeCapture
  attr_reader :ran

  def initialize(&answer)
    @answer = answer || ->(_command) { ["", ProcessStatuses.exited(0)] }
    @ran = []
  end

  def timed(*command, chdir:, limit:)
    @ran.push([command, chdir, limit])
    @answer.call(command)
  end

  def call(*command, chdir:)
    @ran.push([command, chdir])
    @answer.call(command)
  end

  # Each command it ran, without where and how long.
  def commands = @ran.map(&:first)
end
