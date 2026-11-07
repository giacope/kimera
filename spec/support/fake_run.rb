# frozen_string_literal: true

class FakeRun
  attr_reader :runs

  def initialize(status = 0)
    @status = status
    @runs = []
  end

  def run(argv)
    @runs.push(argv)
    Kimera::CLI::Outcome::Ended.new(@status)
  end
end
