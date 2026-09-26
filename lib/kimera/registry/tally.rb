# frozen_string_literal: true

class Kimera::RegistryScan::Tally
  def initialize
    @value = 0
  end

  def next
    @value += 1
  end
end
