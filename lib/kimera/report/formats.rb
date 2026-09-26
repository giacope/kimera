# frozen_string_literal: true

require "json"

module Kimera
  module Report
  end
end

class Kimera::Report::Formats
  NAMES = %w[text json ndjson github sarif].freeze
  REPORTED = %w[survived no_coverage harness_error].freeze
  SUMMARY = %w[schema_version counts mutation_score run].freeze
  RECORDS = { "result" => "results", "leak" => "leaks" }.freeze

  def initialize(io: $stdout)
    @io = io
  end

  def emit(name, report, metadata: nil) = render(name, report.document(metadata))

  def render(name, document) = __send__(normalize(name), document)

  def normalize(name)
    format = String(name)
    return format if NAMES.include?(format)
    raise(Kimera::UsageError, "unknown report format #{format.inspect} (choose: #{NAMES.join(", ")})")
  end

  private

  def json(document) = write(JSON.pretty_generate(document))

  def ndjson(document)
    write(JSON.generate(type: "summary", **document.slice(*SUMMARY)))
    RECORDS.each { |type, key| document.fetch(key).each { |row| write(JSON.generate(type: type, **row)) } }
  end

  def github(document)
    findings(document).each { |result| write("::#{level(result)} #{fields(result)}::#{escaped(message(result))}") }
  end

  def sarif(document)
    write(JSON.pretty_generate(envelope(findings(document).map { |result| finding(result) })))
  end

  def findings(document) = document.fetch("results").select { |result| REPORTED.include?(result.fetch("status")) }

  def level(result) = result["status"] == "survived" ? "error" : "warning"

  def fields(result) = "file=#{property(result.fetch("file"))},line=#{result["line"] || 1}"

  def envelope(results)
    { "$schema" => "https://json.schemastore.org/sarif-2.1.0.json", "version" => "2.1.0" }
      .merge("runs" => [{ "tool" => { "driver" => { "name" => "Kimera" } }, "results" => results }])
  end

  def finding(result)
    { "ruleId" => "kimera/#{result["operator"] || result["status"]}", "level" => level(result) }
      .merge("message" => { "text" => message(result) }, "locations" => [location(result)])
  end

  def location(result)
    region = { "startLine" => result["line"] || 1 }
    { "physicalLocation" => { "artifactLocation" => { "uri" => result["file"] }, "region" => region } }
  end

  def message(result)
    location = [result["file"], result["line"]].compact.join(":")
    "#{result["status"]} mutant ##{result["mutant_id"]} at #{location}: #{result["label"] || result["detail"]}".strip
  end

  def property(value) = value.to_s.gsub(/[%\r\n,:]/) { |char| "%#{char.ord.to_s(16).upcase.rjust(2, "0")}" }

  def escaped(value) = value.to_s.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")

  def write(text) = @io.puts(text)
end
