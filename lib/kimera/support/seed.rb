# frozen_string_literal: true

require "zlib"

module Kimera
end

module Kimera::Seed
  RANGE = 2**31

  module_function

  def derive(seed, test) = (seed ^ Zlib.crc32(test.to_s)) % RANGE
end
