# frozen_string_literal: true

class Kimera::Execution::Shift::Suspect
  def initialize(doubt)
    @doubt = doubt
  end

  def final = @doubt

  def conclude = yield(self)
end
