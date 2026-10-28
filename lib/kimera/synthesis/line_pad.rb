# frozen_string_literal: true

class Kimera::LinePad
  CLOSING = /(?:\bend|[)\]}])\z/

  def initialize(span)
    @span = span
  end

  def kept?(text) = short(text).zero?

  def short(text) = @span.b.count("\n") - text.b.count("\n")

  def texts(text) = short(text).negative? ? [] : [padded(text), closed(text)].uniq

  def padded(text) = "#{text}#{"\n" * short(text)}"

  def closed(text)
    missing = short(text)
    return if missing.negative?
    closing = text.match(CLOSING)
    closing ? "#{closing.pre_match}#{"\n" * missing}#{closing}" : padded(text)
  end

  def fitted(scribe, readback)
    [scribe, scribe.joined].lazy.filter_map { |written| closed(written.text) }.find { |text| readback.faithful?(text) }
  end
end
