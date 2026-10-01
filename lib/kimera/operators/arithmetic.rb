# frozen_string_literal: true

require_relative "binary_swap"

class Kimera::Operators::Arithmetic < Kimera::Operators::BinarySwap
  MUTATIONS = { :+ => [:-], :- => [:+], :* => [:/] }.merge({ :/ => [:*], :% => [:*], :** => [:*] }).freeze
  DIRECTIVE = "op_swap"

  def key = "arithmetic"
end
