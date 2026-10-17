# frozen_string_literal: true

require_relative "regexp_syntax"

class Kimera::Operators::RegexpAnchor < Kimera::Operators::RegexpSyntax
  def key = "regexp_anchor"

  private

  def rewrites(source, token)
    return [] unless token.kind == :anchor
    [rewrite(source, token, "", "drop `#{token.text}`")]
  end
end
