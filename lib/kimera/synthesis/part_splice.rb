# frozen_string_literal: true

require_relative "../scribe"

class Kimera::PartSplice
  VERBATIM = /'/
  SQUIGGLY = "<<~"
  CONTINUED = "\\\n"
  QUOTE = '"'
  INDENT = /\A */
  BLANK = /\A *\n\z/

  def initialize(literal)
    @literal = literal
  end

  def edit(part, rebuilt)
    return unless @literal.opening_loc&.slice&.match?(VERBATIM) == false
    span = part.location
    joined = rebuilt.unescaped.empty? && span.end_offset == @literal.closing_loc.start_offset && last(part, span)
    joined || [span.start_offset, span.end_offset, written(span, rebuilt)]
  end

  def body = parts.first&.location || @literal.content_loc

  private

  def parts = @literal.respond_to?(:parts) ? @literal.parts : []

  def written(span, rebuilt)
    value = Kimera::Scribe.new(rebuilt).text.delete_prefix(QUOTE).delete_suffix(QUOTE)
    rows = [value, *[""] * [lines(span) - 1, 0].max]
    "#{rows.map { "#{margin(span)}#{it}" }.join(CONTINUED)}#{CONTINUED if span.slice.include?("\n")}"
  end

  def last(part, span)
    before = parts.take_while { |each| !each.equal?(part) }.last&.location
    return unless before&.slice&.end_with?("\n")
    return [before.start_offset, span.end_offset, "#{margin(span)}#{CONTINUED}\n"] if blank?(before)
    [span.start_offset - 1, span.end_offset, "#{CONTINUED}\n"]
  end

  def blank?(location) = location.start_column.zero? && location.slice.match?(BLANK)

  def lines(span) = span.slice.count("\n")

  def margin(span) = span.start_column.zero? ? " " * depth : ""

  def depth
    return 0 unless @literal.opening_loc.slice.start_with?(SQUIGGLY)
    starts.filter_map { |text| width(text) }.min || 0
  end

  def starts = parts.select { |part| part.location.start_column.zero? }.map { |part| part.location.slice }

  def width(text)
    indent = text[INDENT].size
    indent unless text[indent] == "\n"
  end
end
