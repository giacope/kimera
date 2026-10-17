# frozen_string_literal: true

require "zlib"

module Kimera
end

class Kimera::Seed
  RANGE = 2**31
  VARIABLE = "KIMERA_SEED"

  def initialize(env = ENV)
    @env = env
  end

  def value = @env[VARIABLE]&.then { |text| Integer(text, 10) }

  def for(test) = (value ^ Zlib.crc32(test.to_s)) % RANGE
end
