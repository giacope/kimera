# frozen_string_literal: true

# A kimera run, as Kimera::CLI::Run takes its arguments: it writes down the
# arguments of every run it is asked for and answers the status it was given.
class FakeRun
  attr_reader :runs

  def initialize(status = 0)
    @status = status
    @runs = []
  end

  def run(argv)
    @runs.push(argv)
    @status
  end
end
