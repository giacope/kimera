# frozen_string_literal: true

require_relative "units/quantity"

# Unit classes are generated at load time: one anonymous Class.new per unit,
# named by const_set, with factors worked out from the table below.
module Units
  INCH_MM = Rational("25.4")
  POUND_G = Rational("453.59237")

  TABLE = {
    length: [
      ["Millimeter", "mm", 1],
      ["Centimeter", "cm", 10],
      ["Meter", "m", 1_000],
      ["Kilometer", "km", 1_000_000],
      ["Inch", "in", INCH_MM],
      ["Foot", "ft", INCH_MM * 12],
      ["Mile", "mi", INCH_MM * 12 * 5_280]
    ],
    mass: [
      ["Gram", "g", 1],
      ["Kilogram", "kg", 1_000],
      ["Pound", "lb", POUND_G],
      ["Ounce", "oz", POUND_G / 16],
      ["Stone", "st", POUND_G * 14]
    ]
  }.freeze

  BY_SYMBOL = TABLE.each_with_object({}) do |(dimension, units), index|
    units.each do |name, symbol, factor|
      klass = Class.new(Quantity) do
        @dimension = dimension
        @factor = Rational(factor)
        @symbol = symbol
      end
      const_set(name, klass)
      index[symbol] = klass
    end
  end.freeze

  def self.parse(text)
    match = /\A\s*(-?\d+(?:\.\d+)?)\s*([a-z]+)\s*\z/.match(text)
    raise ArgumentError, "cannot parse #{text.inspect}" unless match

    unit = BY_SYMBOL.fetch(match[2]) { raise ArgumentError, "unknown unit #{match[2]}" }
    unit.new(match[1].include?(".") ? Rational(match[1]) : match[1].to_i)
  end

  def self.units_for(dimension)
    BY_SYMBOL.values.select { |klass| klass.dimension == dimension }.sort_by(&:factor).map(&:symbol)
  end
end
