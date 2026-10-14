require_relative "grade"

$grade_letters = {}

def letter_for(score)
  $grade_letters[score] ||= Grade.letter(score)
end

class Transcript
  @@passing = {}

  def self.passing?(score)
    return @@passing[score] if @@passing.key?(score)
    @@passing[score] = Grade.passing?(score)
  end
end

module Labels
  class << self
    attr_accessor :memo
  end
  self.memo = {}

  def self.for(score)
    memo.fetch(score) { memo[score] = Grade.label(score) }
  end
end
