# frozen_string_literal: true

require "fileutils"
require "json"
require "stringio"
require_relative "../../report/coloring"
require_relative "../../report/formats"
require_relative "../../report/text"

class Kimera::CLI::Run::Emission
  include Kimera::Report::Coloring

  def initialize(io: $stdout, output: io, color: nil, quiet: false)
    @io = io
    @output = output
    @color = color
    @quiet = quiet
  end

  def emit(report, registry, path: nil, format: "text", metadata: nil, coverage: :hint, log: nil)
    text = rendered(report, registry, coverage, path)
    document = report.document(metadata)
    present(text, format, document)
    save(log, text) if log
    save(path, JSON.pretty_generate(document)) if path
  end

  private

  def rendered(report, registry, coverage, path)
    io = StringIO.new
    Kimera::Report::Text.new(registry, io: io, color: color?).report(report, coverage: coverage, path: path)
    io.string
  end

  def present(text, format, document)
    return Kimera::Report::Formats.new(io: @output).render(format, document) unless format == "text"
    @io.write(text) unless @quiet
  end

  def save(file, text)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, text)
  end
end
