# frozen_string_literal: true

# Parcel pricing. The zone table and tariff are autoloaded: their files (and
# the tables they build at load time) are only read when first referenced.
module Shipping
  class UnknownDestination < KeyError; end

  autoload :ZoneTable, File.expand_path("shipping/zone_table", __dir__)
  autoload :Tariff, File.expand_path("shipping/tariff", __dir__)

  MAX_WEIGHT_G = 30_000

  def self.quote(weight_g, country, express: false)
    raise ArgumentError, "weight must be positive" unless weight_g.positive?
    raise ArgumentError, "too heavy: #{weight_g} g" if weight_g > MAX_WEIGHT_G

    zone = ZoneTable.zone_for(country)
    cents = Tariff.price(zone, weight_g)
    cents = (cents * Tariff::EXPRESS_MULTIPLIER).ceil if express
    cents
  end

  def self.cheapest(weight_g, countries)
    countries.min_by { |c| [quote(weight_g, c), c] }
  end
end
