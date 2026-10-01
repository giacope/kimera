# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::DefaultArgument < Kimera::Operators::Base
  def key = "default_argument"

  def variants(node, **)
    case node
    when OptionalParameterNode, OptionalKeywordParameterNode
      name = node.name
      solo("default => required (#{name})", "required_argument", name: name.to_s)
    end
  end
end
