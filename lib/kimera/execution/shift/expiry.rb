# frozen_string_literal: true

require_relative "lapse"

class Kimera::Execution::Shift::Expiry
  def initialize(test:, message:)
    @test = test
    @message = message
  end

  def passed? = false

  def expired? = true

  def to_h = { "passed" => passed?, "failed_ids" => [test], "failures" => { test => message } }

  private

  attr_reader :test, :message
end
