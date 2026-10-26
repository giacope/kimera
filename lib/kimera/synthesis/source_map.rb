# frozen_string_literal: true

require_relative "../scribe"
require_relative "../rewrite/numbered_params"
require_relative "line_pad"

class Kimera::SourceMap
  attr_reader :source

  def initialize(source)
    @source = source
  end

  def ast
    @_ast ||= Kimera::Rewrite::NumberedParams.new(Kimera::Scribe.parse(@source)).normalize
  end

  def restore(text)
    data = parsed.data_loc
    ending = data ? "#{"\n" unless text.end_with?("\n") || text.empty?}#{data.slice}" : ""
    "#{leading}#{text}#{ending}"
  end

  def lines_kept?(edits)
    edits.all? { |from, to, text| Kimera::LinePad.new(@source.byteslice(from, to - from)).kept?(text) }
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
