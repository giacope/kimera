# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::RegexpLiteral < Kimera::Operators::Base
  class << self
    def key = "regexp"
  end

  def variants(node, **)
    return unless node.is_a?(RegularExpressionNode)
    return if node.unescaped.empty?
    solo("regexp => // (match all)", "regexp_literal", source: "") +
      solo("regexp => /(?!)/ (match none)", "regexp_literal", source: "(?!)")
  end
end
