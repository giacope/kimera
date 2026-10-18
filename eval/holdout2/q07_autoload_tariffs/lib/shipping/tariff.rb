# frozen_string_literal: true

module Shipping
  # Price in cents for a zone and weight. Bands are upper bounds in grams.
  module Tariff
    BANDS = [500, 1_000, 2_000, 5_000, 10_000, 30_000].freeze
    BASE_CENTS = 450
    BAND_STEP_CENTS = 210
    ZONE_SURCHARGE = [nil, 120, 280, 400, 520, 900, 1_400].freeze
    HEAVY_FROM_G = 10_000
    HEAVY_PER_KG_CENTS = 35
    EXPRESS_MULTIPLIER = 1.6

    def self.band_index(weight_g)
      BANDS.index { |limit| weight_g <= limit }
    end

    def self.price(zone, weight_g)
      band = band_index(weight_g)
      cents = BASE_CENTS + (band * BAND_STEP_CENTS) + ZONE_SURCHARGE.fetch(zone)
      if weight_g > HEAVY_FROM_G
        extra_kg = ((weight_g - HEAVY_FROM_G) / 1_000.0).ceil
        cents += extra_kg * HEAVY_PER_KG_CENTS
      end
      cents
    end
  end
end
