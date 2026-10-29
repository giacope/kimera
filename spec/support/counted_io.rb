# frozen_string_literal: true

require "stringio"

# A string stream that counts how often it was flushed.
class CountedIO < StringIO
  attr_reader :flushes

  def initialize(...)
    super
    @flushes = 0
  end

  def flush
    @flushes += 1
    super
  end
end
