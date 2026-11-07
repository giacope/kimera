# frozen_string_literal: true

require "stringio"

class CountedIO < StringIO
  attr_reader :flushed

  def initialize(...)
    super
    @flushed = []
  end

  def flush
    @flushed.push(string.lines.size)
    super
  end

  def flushes = @flushed.size
end
