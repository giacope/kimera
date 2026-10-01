# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::RegexpLiteral < Kimera::Operators::Base
  def key = "regexp"

  def variants(node, **)
    return unless node.is_a?(RegularExpressionNode)
    return if node.unescaped.empty?
    solo("regexp => // (match all)", "regexp_literal", source: "") +
      solo("regexp => /(?!)/ (match none)", "regexp_literal", source: "(?!)")
  end
end
