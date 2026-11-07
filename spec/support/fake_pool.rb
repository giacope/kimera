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
  def initialize(index, notes, pipes = Kimera::Execution::Pool::Channels.new(*IO.pipe, *IO.pipe))
    @index = index
    @notes = notes
    @pipes = pipes
  end

  def child! = @pipes.child!

  def prepare(database) = Kimera::Execution::Pool::Duty.new(:serve, @index, @pipes).prepare(database)

  def run(shift)
    $stdout.print("loud")
    $stdout.flush
    parent = @pipes.to_a.values_at(1, 2)
    note("run", shift.class.name, Process.getpgrp == Process.pid, *parent.map(&:closed?))
  end

  def pulse = note("pulse")

  def retire(database, error) = note("retire", database.forked, error&.class&.name, error&.message)

  private

  def note(*seen)
    @notes.puts(JSON.generate(seen))
    @notes.flush
  end
end
