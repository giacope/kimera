# frozen_string_literal: true

require_relative "base"
require_relative "regexp_tokens"

class Kimera::Operators::RegexpSyntax < Kimera::Operators::Base
  def variants(node, **)
    source = pattern(node)
    return unless source
    Kimera::Operators::RegexpTokens.new(source).tokens.flat_map { |token| rewrites(source, token) }
  end

  private

  def pattern(node)
    return unless node.is_a?(RegularExpressionNode) && !node.extended?
    source = node.unescaped
    source if source == node.content.gsub("\\/", "/") && source.valid_encoding?
  end

  def rewrite(source, token, replacement, label)
    offset = token.offset
    edited = source[0, offset] + replacement + source[(offset + token.text.length)..]
    mutation("regexp: #{label}", "regexp_source", source: edited)
  end
end
