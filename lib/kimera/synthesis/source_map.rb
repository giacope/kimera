# frozen_string_literal: true

require_relative "../scribe"
require_relative "../rewrite/numbered_params"

class Kimera::SourceMap
  attr_reader :source

  def initialize(source)
    @source = source
  end

  def ast
    @_ast ||= Kimera::Rewrite::NumberedParams.new(Kimera::Scribe.parse(@source)).normalize
  end

  def restore(source)
    prefix = comments.join("\n")
    prefix.empty? ? source : "#{prefix}\n#{source}"
  end

  def splice(edits)
    text =
      edits.sort_by(&:first).reverse_each.with_object(@source.b) do |(from, to, replacement), spliced|
        spliced[from...to] = replacement.b
      end
    text.force_encoding(@source.encoding)
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
end
