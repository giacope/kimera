# frozen_string_literal: true

require_relative "live"
require_relative "log"

module Kimera
  module Report
  end
end

class Kimera::Report::Screen
  MODES = { true => :on, false => :off }.freeze

  class << self
    def for(io, preference) = public_send(MODES.fetch(preference, :auto), io)

    def on(io) = new(io, enabled: true, interactive: tty?(io))

    def off(io) = new(io, enabled: false, interactive: tty?(io))

    def auto(io)
      tty = tty?(io)
      new(io, enabled: tty, interactive: tty)
    end

    private

    def tty?(io) = io.tty?
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
    @interactive ? Kimera::Report::Live.for(@io) : Kimera::Report::Log.new(@io)
  end
end
