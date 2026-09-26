# frozen_string_literal: true

# A small logic class exercised by a Minitest suite, mirroring the kinds of
# comparison/boolean mutations Kimera targets.
class Scorer
  def initialize(threshold: 10)
    @threshold = threshold
  end

  def pass?(score)
    score >= @threshold
  end

  def grade(score)
    if score >= 90
      :a
    elsif score >= 70
      :b
    else
      :c
    end
  end

  def bonus?(score, streak)
    score > 50 && streak > 3
  end

  # Deliberately under-tested: only the `true` side is asserted, so the
  # boundary mutant `> 100` -> `>= 100` survives.
  def high_roller?(total)
    total > 100
  end
end
