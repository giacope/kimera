# frozen_string_literal: true

class FakeExits
  attr_reader :codes

  def initialize
    @codes = []
  end

  def exit!(code) = @codes.push(code)

  def exit(code) = @codes.push(code)
end
