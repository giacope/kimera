# frozen_string_literal: true

module Kimera
end

class Kimera::CLI
end

class Kimera::CLI::Suggestion
  MAX_EDITS = 3

  def initialize(known)
    @known = known
  end

  def hint(word)
    nearest = @known.min_by { |candidate| distance(word, candidate) }
    nearest && distance(word, nearest) <= MAX_EDITS ? "; did you mean #{nearest.inspect}?" : ""
  end

  private

  def distance(left, right)
    left.each_char.with_index(1).reduce(origin(right)) do |above, (char, index)|
      below(above, right.each_char.map { |other| other == char ? 0 : 1 }, index)
    end.last
  end

  def origin(word) = (0..word.length).to_a

  def below(above, costs, index)
    costs.each_with_index.reduce([index]) do |row, (cost, column)|
      row << [above[column + 1] + 1, row[column] + 1, above[column] + cost].min
    end
  end
end
