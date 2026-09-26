# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::StringLiteral < Kimera::Operators::Base
  class << self
    def key = "string_literal"
  end

  def variants(node, **)
    return unless node.is_a?(StringNode)
    value = node.unescaped
    return if value.empty?
    solo("#{excerpt(value)} => \"\"", "string_literal", value: "")
  end

  private

  def excerpt(value)
    value.inspect[0, 30]
  end
end
