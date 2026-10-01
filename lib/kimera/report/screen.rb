# frozen_string_literal: true

require_relative "live"
require_relative "log"

module Kimera
  module Report
  end
end

class Kimera::Report::Screen
  MODES = [true, false].freeze

  class << self
    def of(io, preference)
      tty = io.tty?
      new(io, enabled: MODES.include?(preference) ? preference : tty, interactive: tty)
    end
  end

  def initialize(io, enabled:, interactive:)
    @io = io
    @enabled = enabled
    @interactive = interactive
  end

  def enabled? = @enabled

  def interactive? = @interactive

  def colored? = @enabled && !ENV.key?("NO_COLOR")

  def surface
    @interactive ? Kimera::Report::Live.new(@io, columns: columns) : Kimera::Report::Log.new(@io)
  end

  private

  def columns
    @io.winsize.fetch(1)
  rescue NoMethodError, SystemCallError
    nil
  end
end
