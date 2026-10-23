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

  # A whole-file rewrite keeps what the tree does not carry: the leading
  # comment section (every magic comment, in any spelling) and `__END__` with
  # its data.
  def restore(text)
    data = parsed.data_loc
    ending = data ? "#{"\n" unless text.end_with?("\n") || text.empty?}#{data.slice}" : ""
    "#{leading}#{text}#{ending}"
  end

  def splice(edits)
    text =
      edits.sort_by { |from, to, _| [from, to] }.reverse_each.with_object(@source.b) do |(from, to, text), spliced|
        spliced[from...to] = text.b
      end
    text.force_encoding(@source.encoding)
  end

  private

  def parsed = @_parsed ||= Kimera::Syntax.parse(@source)

  def leading
    head = @source.b.byteslice(0, code)
    head.byteslice(0, (head.rindex("\n") || -1) + 1).force_encoding(@source.encoding)
  end

  def code
    first = parsed.value.statements.body.first
    first ? first.location.start_offset : parsed.data_loc&.start_offset || @source.bytesize
  end
end
