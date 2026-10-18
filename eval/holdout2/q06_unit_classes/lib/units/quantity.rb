# frozen_string_literal: true

module Units
  class IncompatibleUnits < ArgumentError; end

  # Base for every generated unit class. Each concrete class carries its
  # dimension, its factor to the dimension's base unit and a symbol.
  class Quantity
    include Comparable

    class << self
      attr_reader :dimension, :factor, :symbol
    end

    attr_reader :value

    def initialize(value)
      @value = value.is_a?(Float) ? value.rationalize(Rational(1, 1_000_000)) : Rational(value)
    end

    def to_base
      value * self.class.factor
    end

    def to(unit)
      check!(unit)
      unit.new(to_base / unit.factor)
    end

    def +(other)
      self.class.new(value + other.to(self.class).value)
    end

    def -(other)
      self.class.new(value - other.to(self.class).value)
    end

    def *(scalar)
      raise TypeError, "can only scale by a number" unless scalar.is_a?(Numeric)

      self.class.new(value * scalar)
    end

    def <=>(other)
      return nil unless other.is_a?(Quantity) && other.class.dimension == self.class.dimension

      to_base <=> other.to_base
    end

    def round(digits = 2)
      value.round(digits).to_f
    end

    def to_s
      number = value.denominator == 1 ? value.to_i : value.to_f.round(3)
      "#{number} #{self.class.symbol}"
    end

    private

    def check!(unit)
      return if unit.dimension == self.class.dimension

      raise IncompatibleUnits, "cannot convert #{self.class.dimension} to #{unit.dimension}"
    end
  end
end
