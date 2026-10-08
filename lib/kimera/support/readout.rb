# frozen_string_literal: true

require_relative "duration"

module Kimera
end

module Kimera::Readout
  module_function

  def label(id, entry)
    name = entry["name"]
    return id unless name
    [entry["location"], name].compact.join("  ")
  end

  def lines(text)
    text.to_s.split("\n").map(&:rstrip).reject(&:empty?)
  end

  def brief(seconds) = Kimera::Duration.new(seconds).brief
end
