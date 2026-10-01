# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::KernelCoercion < Kimera::Operators::Base
  COERCIONS = %i[Array String Integer Float].freeze

  def key = "kernel_coercion"

  def variants(node, **)
    return unless call(node).bare?(COERCIONS)
    return unless unary?(node)
    solo("delete #{node.name}()", "unwrap_argument")
  end
end
