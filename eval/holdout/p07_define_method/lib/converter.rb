class Converter
  SCALE = { mm: 1, cm: 10, m: 1000, km: 1_000_000 }.freeze

  SCALE.each do |unit, factor|
    define_method("to_#{unit}") do |mm|
      raise ArgumentError, "negative" if mm < 0

      mm % factor == 0 ? mm / factor : (mm.to_f / factor).round(2)
    end
  end

  [[:short?, 100], [:long?, 10_000]].each do |name, limit|
    define_method(name) { |mm| name == :short? ? mm < limit : mm >= limit }
  end
end
