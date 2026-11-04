# frozen_string_literal: true

require_relative "frame"

module Kimera
  module Report
  end
end

class Kimera::Report::Surface
  def committed(frame) = closed(frame) { commit(frame) }

  def cleared(frame) = closed(frame) { wipe(frame) }

  private

  def closed(frame) = frame.drawn? ? [yield] : []
end
