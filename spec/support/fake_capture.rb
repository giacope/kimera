# frozen_string_literal: true

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

  def commands = @ran.map(&:first)
end
