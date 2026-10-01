# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::OpAssign < Kimera::Operators::Base
  MUTATIONS = { :+ => :-, :- => :+, :* => :/ }.merge({ :/ => :*, :% => :* }).freeze

  def key = "op_assign"

  def variants(node, **)
    operator = syntax(node).operator
    to = MUTATIONS[operator]
    return unless to
    solo("#{operator}= => #{to}=", "op_asgn_swap", to: to.to_s)
  end
end
