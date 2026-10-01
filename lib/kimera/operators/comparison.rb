# frozen_string_literal: true

require_relative "binary_swap"

class Kimera::Operators::Comparison < Kimera::Operators::BinarySwap
  MUTATIONS = { :> => %i[>= <], :>= => %i[> <=], :< => %i[<= >] }
    .merge({ :<= => %i[< >=], :== => [:!=], :!= => [:==] }).freeze
  DIRECTIVE = "comparison"

  def key = "comparison"
end
