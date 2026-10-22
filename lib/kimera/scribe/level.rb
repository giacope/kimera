# frozen_string_literal: true

module Kimera
  class Scribe
    module Level
      STATEMENT = 0
      EXPRESSION = 1
      ASSIGNMENT = 2
      KEYWORD = 3
      TERNARY = 4
      RANGE = 5
      OR = 6
      AND = 7
      EQUALITY = 8
      PRIMARY = 18
      BINARY = {
        "<=>": 8, "==": 8, "===": 8, "!=": 8, "=~": 8, "!~": 8, ">": 9, ">=": 9, "<": 9, "<=": 9,
        "|": 10, "^": 10, "&": 11, "<<": 12, ">>": 12, "+": 13, "-": 13, "*": 14, "/": 14, "%": 14, "**": 16
      }.freeze
      PREFIX = { "-@": 15, "+@": 17, "!": 17, "~": 17 }.freeze
      NONASSOCIATIVE = [EQUALITY, RANGE].freeze
    end
  end
end
