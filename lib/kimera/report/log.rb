# frozen_string_literal: true

require_relative "surface"

class Kimera::Report::Log < Kimera::Report::Surface
  HEARTBEAT_EVERY = 30.0

  def cadence = HEARTBEAT_EVERY

  def commit = clear

  private

  def frame(text) = "#{text}\n"

  def wipe = @io.flush
end
