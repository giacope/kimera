# frozen_string_literal: true

module Kimera
  class Scribe
    class Number
      def initialize(value)
        @value = value
      end

      def text
        case @value
        when Complex then imaginary
        when Rational then rational
        when Float then float
        else @value.to_s
        end
      end

      private

      def imaginary
        return "Complex(#{@value.real.inspect}, #{@value.imaginary.inspect})" unless @value.real.zero?
        "#{Number.new(@value.imaginary).text}i"
      end

      def float
        return @value.to_s if @value.finite?
        return "Float::NAN" if @value.nan?
        @value.positive? ? "1e999" : "-1e999"
      end

      def rational
        denominator = @value.denominator
        return "#{@value.numerator}r" if denominator == 1
        places = (1..64).find { |count| ((10**count) % denominator).zero? }
        places ? "#{decimal(places)}r" : "Rational(#{@value.numerator}, #{denominator})"
      end

      def decimal(places)
        digits = (@value.abs * (10**places)).to_i.to_s.rjust(places + 1, "0")
        "#{"-" if @value.negative?}#{digits[0...-places]}.#{digits[-places..]}"
      end
    end
  end
end
