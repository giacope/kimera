# frozen_string_literal: true

require_relative "duration"

module Kimera
end

class Kimera::Readout
  Label =
    Data.define(:id, :entry) do
      def text
        name = entry["name"]
        return id unless name
        [entry["location"], name].compact.join("  ")
      end
    end

  def initialize(value)
    @value = value
  end

  def lines = @value.to_s.split("\n").map(&:rstrip).reject(&:empty?)

  def brief = Kimera::Duration.new(@value).brief
end
