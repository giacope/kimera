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

  def given = Array(@env[VARIABLE]).map { |text| Integer(text, 10) }

  def for(test) = given.map { |value| (value ^ Zlib.crc32(test.to_s)) % RANGE }
end
