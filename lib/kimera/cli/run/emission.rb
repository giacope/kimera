# frozen_string_literal: true

require "stringio"
require_relative "../../report/palette"
require_relative "../../report/formats"
require_relative "../../report/text"
require_relative "emission/copies"
require_relative "emission/delivery"
require_relative "emission/page"

class Kimera::CLI::Run::Emission
  NARRATED = %w[text github].freeze

  def initialize(io: $stdout, output: io, color: nil, quiet: false)
    @io = io
    @output = output
    @color = color
    @quiet = quiet
  end

  def emit(report, registry, delivery) = delivery.deliver(report, registry, self)

  def rendered(report, registry, **) = captured(registry) { |text| text.report(report, **) }

  def saved(report, registry, path, **) = captured(registry) { |text| text.saved(report, path, **) }

  def present(text, format, document)
    @io.write(text) if NARRATED.include?(format) && !@quiet
    Kimera::Report::Formats.new(io: @output).render(format, document) unless format == "text"
  end

  private

  def captured(registry)
    io = StringIO.new
    yield(Kimera::Report::Text.new(registry, io: io, palette: Kimera::Report::Palette.new(@io, @color)))
    io.string
  end
end
