require_relative "band"

module Bands
  @seen = {}

  def self.of(age)
    @seen[age] ||= Band.of(age)
  end
end
