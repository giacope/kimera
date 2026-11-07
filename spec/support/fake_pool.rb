# frozen_string_literal: true

require "json"
require "kimera/execution/pool_driver"

class FakeShift
  attr_reader :served

  def initialize
    @served = []
  end

  def coverage(request, response) = @served.push([:coverage, request, response])
end

class FakeDatabases
  attr_reader :forked, :exited

  def initialize(&setup)
    @setup = setup || proc {}
    @forked = []
    @exited = []
  end

  def after_fork(index)
    @forked.push(index)
    @setup.call
  end

  def before_exit(index) = @exited.push(index)
end

class FakeDuty
  attr_reader :index, :pipes

  def initialize(index, notes, pipes = Kimera::Execution::Pool::Channels.new(*IO.pipe, *IO.pipe))
    @index = index
    @notes = notes
    @pipes = pipes
  end

  def run(shift)
    $stdout.print("loud")
    $stdout.flush
    note("run", shift.class.name, Process.getpgrp == Process.pid, pipes.req_w.closed?, pipes.res_r.closed?)
  end

  def pulse = note("pulse")

  def retire(database, error) = note("retire", database.forked, error&.class&.name, error&.message)

  private

  def note(*seen)
    @notes.puts(JSON.generate(seen))
    @notes.flush
  end
end
