# frozen_string_literal: true

require "json"
require_relative "../error"

module Kimera
end

class Kimera::CLI
end

class Kimera::CLI::ReportFile
  DEFAULT = "tmp/kimera/report.json"

  def initialize(path)
    @path = path
  end

  def document
    @_document ||= JSON.parse(File.read(@path, encoding: Encoding::UTF_8))
  rescue JSON::ParserError => error
    raise(Kimera::UsageError, "unreadable report #{@path}: #{error.message}")
  end

  def results = document.fetch("results", [])

  def row(token) = results.find { |result| [result["mutant_id"].to_s, result["key"]].include?(token.to_s) }
end
