# frozen_string_literal: true

class Kimera::Execution::Shift::Interruption < StandardError
  def initialize(error, killers)
    super()
    @error = error
    @killers = killers
  end

  def crashed(subject, limit) = [subject.crashed(@error, limit), @killers]
end
