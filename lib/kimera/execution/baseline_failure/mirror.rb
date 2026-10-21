# frozen_string_literal: true

class Kimera::Execution::BaselineFailure::Mirror
  IN_USE = /ObjectInUse|being accessed by other users/
  HELD = "  the suite drops and re-creates its test database while it loads, and another session still held it: " \
    "kimera closes its own connections before it starts a mirror, so look for another process on that database " \
    "(a console, a server, a second test run)"

  def initialize(reason, hint)
    @reason = reason
    @hint = hint
  end

  def to_s
    "isolated baseline is not green: the unmutated suite fails in a mirror of the project\n  " \
      "#{@reason.gsub("\n", "\n    ")}\n#{@hint}#{held}"
  end

  private

  def held = @reason.match?(IN_USE) ? "\n#{HELD}" : ""
end
