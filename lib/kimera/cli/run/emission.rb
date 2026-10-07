# frozen_string_literal: true

require "fileutils"
require "json"
require "stringio"
require_relative "../../report/coloring"
require_relative "../../report/formats"
require_relative "../../report/text"

class Kimera::CLI::Run::Emission
  include Kimera::Report::Coloring

  NARRATED = %w[text github].freeze

  Settings =
    Data.define(:path, :format, :metadata, :coverage, :log, :scope, :summary) do
      def deliver(report, registry, emission)
        text = emission.rendered(report, registry, scope: scope, coverage: coverage, path: path)
        document = report.document(metadata)
        emission.present(text, format, document)
        keep(text, document)
      end
      private
      def keep(text, document)
        write(log, text) if log
        write(path, JSON.pretty_generate(document)) if path
        append(document) if summary
      end

      def append(document)
        FileUtils.mkdir_p(File.dirname(summary))
        File.open(summary, "a") { |file| Kimera::Report::Formats.new(io: file).render("markdown", document) }
      end

      def write(file, text)
        FileUtils.mkdir_p(File.dirname(file))
        File.write(file, text)
      end
    end
  PLAIN = Settings.new(path: nil, format: "text", metadata: nil, coverage: :hint, log: nil, scope: nil, summary: nil)

  def initialize(io: $stdout, output: io, color: nil, quiet: false)
    @io = io
    @output = output
    @color = color
    @quiet = quiet
  end

  def emit(report, registry, **settings) = PLAIN.with(**settings).deliver(report, registry, self)

  def rendered(report, registry, **)
    io = StringIO.new
    Kimera::Report::Text.new(registry, io: io, color: color?).report(report, **)
    io.string
  end

  def present(text, format, document)
    @io.write(text) if NARRATED.include?(format) && !@quiet
    Kimera::Report::Formats.new(io: @output).render(format, document) unless format == "text"
  end
end
