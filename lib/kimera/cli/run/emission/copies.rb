# frozen_string_literal: true

require "fileutils"
require "json"
require_relative "../../../report/formats"

class Kimera::CLI::Run::Emission; end

class Kimera::CLI::Run::Emission::Copies
  def initialize(path, log, summary)
    @path = path
    @log = log
    @summary = summary
  end

  def keep(text, document)
    write(@log, text) if @log
    write(@path, JSON.pretty_generate(document)) if @path
    append(document) if @summary
  end

  private

  def append(document)
    FileUtils.mkdir_p(File.dirname(@summary))
    File.open(@summary, "a") { |file| Kimera::Report::Formats.new(io: file).render("markdown", document) }
  end

  def write(file, text)
    FileUtils.mkdir_p(File.dirname(file))
    File.write(file, text)
  end
end
