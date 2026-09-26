# frozen_string_literal: true

require_relative "../support/unparse"
require_relative "../rewrite/numbered_params"

class Kimera::SourceMap
  attr_reader :source

  def initialize(source)
    @source = source
  end

  def ast
    @_ast ||= Kimera::Rewrite::NumberedParams.normalize(Kimera::Unparse.parse(@source))
  end

  def span(expr)
    [bytes[expr.begin_pos], bytes[expr.end_pos]]
  end

  def restore(source)
    prefix = comments.join("\n")
    prefix.empty? ? source : "#{prefix}\n#{source}"
  end

  MAGIC_COMMENT =
    /\A#\s*(?:-\*-.*-\*-|(?:frozen_string_literal|encoding|coding|warn_indent|shareable_constant_value)\s*:)/i
  private_constant :MAGIC_COMMENT

  private

  def comments
    first, second = @source.lines
    shebang = first&.start_with?("#!") ? first : nil
    candidate = shebang ? second : first
    [shebang, (candidate&.match?(MAGIC_COMMENT) ? candidate : nil)].compact.map(&:chomp)
  end

  def bytes
    @_bytes ||= @source.each_char.map(&:bytesize).each_with_object([0]) { |size, map| map << (map.last + size) }
  end
end
