# frozen_string_literal: true

require_relative "binary_swap"

class Kimera::Operators::Comparison < Kimera::Operators::BinarySwap
  MUTATIONS = { :> => %i[>= <], :>= => %i[> <=], :< => %i[<= >] }
    .merge({ :<= => %i[< >=], :== => [:!=], :!= => [:==] }).freeze
  DIRECTIVE = "comparison"

  class << self
    def key = "comparison"
  end
end
