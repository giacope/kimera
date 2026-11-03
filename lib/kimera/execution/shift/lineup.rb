# frozen_string_literal: true

require_relative "finding"

class Kimera::Execution::Shift::Lineup
  include Enumerable

  def initialize(active, tests)
    @active = active
    @tests = tests
  end

  def each(&) = @tests.each { |test| yield(@active, test) }

  def found(found) = Kimera::Execution::Shift::Finding.new(@active, @tests, found)
end
