# frozen_string_literal: true

require "yaml"
require_relative "../report_file"
require_relative "entry"

class Kimera::CLI::Baseline::Ledger
  attr_reader :path, :report

  def initialize(path, report)
    @path = path
    @report = report
  end

  def document = @_document ||= YAML.safe_load_file(@path) || {}

  def entries = @_entries ||= Array(document["ignore"]).map { |fields| judged(fields) }

  private

  def judged(fields)
    scoped = rows.select { |row| File.fnmatch?(fields["file"].to_s, row["file"].to_s, File::FNM_PATHNAME) }
    Kimera::CLI::Baseline::Entry.new(fields, scoped, missing: missing)
  end

  def rows = @_rows ||= parsed.fetch("results", [])

  def missing = parsed.dig("run", "since") ? :out_of_scope : :stale

  def parsed = @_parsed ||= Kimera::CLI::ReportFile.new(@report).document
end
