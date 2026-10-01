# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::NumericLiteral < Kimera::Operators::Base
  IntegerTargets =
    Data.define(:value) do
      include Enumerable
      def each(&) = targets.uniq.each(&)
      private
      def targets
        [value - 1, value + 1].tap { |all| all << 0 unless value.zero? }
      end
    end
  def key = "numeric_literal"

  def variants(node, **)
    case node
    in IntegerNode(value:) then integers(value)
    in FloatNode(value:) then floats(value)
    else nil
    end
  end

  private

  def integers(value)
    IntegerTargets.new(value).map do |to|
      Kimera::Operators::Variant.new(label: "#{value} => #{to}", directive: directive("integer_literal", value: to))
    end
  end

  def floats(value)
    shifted = value + 1.0
    solo("#{value} => #{shifted}", "float_literal", value: shifted)
  end
end
