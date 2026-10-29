# frozen_string_literal: true

require_relative "lapse"

class Kimera::Execution::Shift::Stall
  include Kimera::Execution::Shift::Lapse

  def initialize(test, expiry, control)
    @test = test
    @expiry = expiry
    @control = control
  end

  def detail = "#{expiry} with the mutant on; alone with it off, the test passed in #{control.round(2)}s"

  private

  attr_reader :test, :expiry, :control
end
