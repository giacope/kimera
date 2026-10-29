# frozen_string_literal: true

# Kernel's exits, as a forked child leaves through them: each writes its code
# down instead of exiting.
class FakeExits
  attr_reader :codes

  def initialize
    @codes = []
  end

  def exit!(code) = @codes.push(code)
end
