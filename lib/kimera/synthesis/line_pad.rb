# frozen_string_literal: true

# A span's lines, for a text written over it so that every line after it
# keeps its number: the text as it is when it breaks as many lines, and with
# the line breaks it lacks after it, or before its closing `end`, `}`, `)` or
# `]` (`closed`, which reads the same wherever the text stands), when it
# breaks fewer. None when it breaks more.
class Kimera::LinePad
  CLOSING = /(?:\bend|[)\]}])\z/

  def initialize(span)
    @span = span
  end

  def kept?(text) = short(text).zero?

  # The line breaks a text lacks, whatever bytes it holds.
  def short(text) = @span.b.count("\n") - text.b.count("\n")

  def texts(text) = short(text).negative? ? [] : [padded(text), closed(text)].uniq

  def padded(text) = "#{text}#{"\n" * short(text)}"

  def closed(text)
    missing = short(text)
    return if missing.negative?
    closing = text.match(CLOSING)
    closing ? "#{closing.pre_match}#{"\n" * missing}#{closing}" : padded(text)
  end

  # A node's writing that fits the span: as Scribe lays it out, else on one line.
  def fitted(scribe) = [scribe, scribe.joined].lazy.filter_map { |written| closed(written.text) }.first
end
