# frozen_string_literal: true

require_relative "regexp_syntax"

class Kimera::Operators::RegexpQuantifier < Kimera::Operators::RegexpSyntax
  SWAPS = { "+" => "*", "*" => "+" }.freeze
  BOUNDS = /\A\{(\d*)(,?)(\d*)\}/

  def key = "regexp_quantifier"

  private

  def rewrites(source, token)
    return [] unless token.kind == :quantifier
    text = token.text
    replacements(text).map { |replacement| rewrite(source, token, replacement, "`#{text}` => `#{replacement}`") }
  end

  def replacements(text)
    head = text[0]
    return [SWAPS.fetch(head) + text[1..]] if SWAPS.key?(head)
    return [""] if head == "?"
    bounds(*text.match(BOUNDS).captures).map { |lower, upper| "{#{lower}#{upper}}#{text[/\}(.*)\z/, 1]}" }
  end

  def bounds(lower, comma, upper)
    return exact(Integer(lower)) if comma.empty?
    [
      ([(Integer(lower) - 1).to_s, ",#{upper}"] if lower.to_i.positive?),
      ([lower.to_s, ",#{Integer(upper) + 1}"] unless upper.empty?)
    ].compact
  end

  def exact(count) = [([(count - 1).to_s, ""] if count > 1), [(count + 1).to_s, ""]].compact
end
