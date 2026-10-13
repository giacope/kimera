require_relative "macros"

class Widget
  extend Macros

  LIMITS = [5, 50].map { |n| n > 10 ? n * 2 : n }
  SMALL = ->(size) { size < 10 }
  LARGE = lambda { |size| size > 100 }
  ROUND = proc { |size| size % 10 == 0 }

  rule(:sane) { |size| size > 0 && size < 1000 }

  def initialize(size)
    @size = size
  end

  attr_reader :size

  def plain? = size > 1

  define_method(:tiny?) { size < 3 && size != 0 }

  define_method(:huge?) do
    size >= 500 || size == -1
  end

  define_singleton_method(:valid_size?) { |value| value.is_a?(Integer) && value > 0 }

  %i[odd even].each do |kind|
    define_method(:"#{kind}_sized?") { kind == :odd ? size.odd? : !size.odd? }
  end

  def self.limit = LIMITS.last

  def small? = SMALL.call(size)

  def large? = LARGE.call(size)

  def round? = ROUND.call(size)

  def sane? = self.class.rules.fetch(:sane).call(size)
end
