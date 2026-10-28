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

  def fits(scribe, readback)
    written = [scribe, scribe.joined].lazy.filter_map { |each| closed(each.text) }
    written.select { |text| readback.faithful?(text) }.first(1)
  end
end
