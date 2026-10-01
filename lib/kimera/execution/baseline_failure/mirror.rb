# frozen_string_literal: true

class Kimera::Execution::BaselineFailure::Mirror
  def initialize(reason, hint)
    @reason = reason
    @hint = hint
  end

  def to_s
    "isolated baseline is not green: the unmutated suite fails in a mirror of the project\n  " \
      "#{@reason.gsub("\n", "\n    ")}\n#{@hint}"
  end
end
