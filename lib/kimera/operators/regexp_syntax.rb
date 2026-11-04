# frozen_string_literal: true

require_relative "base"
require_relative "regexp_tokens"

class Kimera::Operators::RegexpSyntax < Kimera::Operators::Base
  def variants(node, **)
    patterns(node).flat_map do |source|
      Kimera::Operators::RegexpTokens.new(source).tokens.flat_map { |token| rewrites(source, token) }
    end
  end

  private

  def patterns(node)
    return [] unless node.is_a?(RegularExpressionNode) && !node.extended?
    source = node.unescaped
    source == node.content.gsub("\\/", "/") && source.valid_encoding? ? [source] : []
  end

  def rewrite(source, token, replacement, label)
    mutation("regexp: #{label}", "regexp_source", source: token.splice(source, replacement))
  end
end
