# frozen_string_literal: true

module Kimera
  class Scribe
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
    INDENT = "  "
    NAMED = %i[
      local_variable_write_node local_variable_target_node local_variable_operator_write_node
      local_variable_or_write_node local_variable_and_write_node required_parameter_node optional_parameter_node
      rest_parameter_node required_keyword_parameter_node optional_keyword_parameter_node
      keyword_rest_parameter_node block_parameter_node block_local_variable_node
    ].freeze
    NO_NAMES = Set.new.freeze
    private_constant(
      :STATEMENT, :EXPRESSION, :ASSIGNMENT, :KEYWORD, :TERNARY, :RANGE, :OR, :AND, :EQUALITY, :PRIMARY, :BINARY,
      :PREFIX, :NONASSOCIATIVE, :INDENT, :NAMED, :NO_NAMES
    )
  end
end
