# frozen_string_literal: true

require_relative "duration"

module Kimera
end

class Kimera::Readout
  class Label
    def initialize(id, entry)
      @id = id
      @entry = entry
    end

    def text
      name = entry["name"]
      return id unless name
      [entry["location"], name].compact.join("  ")
    end

    private

    attr_reader :id, :entry
  end

  def initialize(value)
    @value = value
  end

  def lines = @value.to_s.split("\n").map(&:rstrip).reject(&:empty?)

  def brief = Kimera::Duration.new(@value).brief

  def quoted(sign, indent)
    first, *rest = @value.to_s.split("\n")
    ["#{indent}#{sign} #{first}", *rest.map { |line| "#{indent}  #{line}" }]
  end
end
