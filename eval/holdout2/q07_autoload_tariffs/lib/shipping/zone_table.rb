# frozen_string_literal: true

module Shipping
  # Country code => zone, inverted once from the zone lists when this file
  # is autoloaded.
  module ZoneTable
    ZONES = {
      1 => %w[DE],
      2 => %w[AT BE DK FR LU NL],
      3 => %w[ES IT PL PT SE CZ],
      4 => %w[GB CH NO],
      5 => %w[US CA]
    }.freeze

    BY_COUNTRY = ZONES.each_with_object({}) do |(zone, countries), index|
      countries.each { |code| index[code] = zone }
    end.freeze

    REST_OF_WORLD = ZONES.keys.max + 1

    def self.zone_for(country)
      code = country.to_s.strip.upcase
      raise UnknownDestination, "bad country code #{country.inspect}" unless code.match?(/\A[A-Z]{2}\z/)

      BY_COUNTRY.fetch(code, REST_OF_WORLD)
    end
  end
end
