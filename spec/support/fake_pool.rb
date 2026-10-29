# frozen_string_literal: true

require "json"
require "kimera/execution/pool_driver"

# A shift a pool duty runs: it writes down each errand it serves, with the
# pipe ends it serves it on.
class FakeShift
  attr_reader :served

  def initialize
    @served = []
  end

  def coverage(request, response) = @served.push([:coverage, request, response])
end

# A worker's test databases, as Kimera::Execution::WorkerDatabases sets them
# up after a fork and tears them down before the worker exits: it writes down
# each worker, and its setup runs the block it was given.
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

# A pool duty for worker +index+, on real pipes. It writes down on +notes+,
# a JSON line each, what the process that ran it looked like (whether it led
# its own process group and had closed the parent's pipe ends), each pulse,
# and how it was retired; from a forked worker, +notes+ is the pipe the
# parent reads. It prints to standard output as it runs, as tests do.
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
