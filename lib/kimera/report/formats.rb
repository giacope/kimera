# frozen_string_literal: true

require "json"
require_relative "markdown"

module Kimera
  module Report
  end
end

class Kimera::Report::Formats
  NAMES = %w[text json ndjson github sarif markdown].freeze
  GITHUB_SHOWN = 10
  FINDINGS = { "survived" => "surviving", "no_coverage" => "uncovered", "harness_error" => "unjudged" }.freeze
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

  def markdown(document) = @io.write(Kimera::Report::Markdown.new(document, FINDINGS).render)

  def github(document)
    groups = findings(document).group_by { |result| [level(result), result.fetch("file"), result["line"] || 1] }
    groups.each_value { |results| annotate(results) }
    crowded(groups.keys.map(&:first).tally.values)
  end

  def annotate(results) = write("::#{level(results.first)} #{fields(results)}::#{escaped(described(results))}")

  def described(results) = results.map { |result| [message(result), *diff(result)].join("\n") }.join("\n\n")

  def diff(result)
    original = result["original"]
    mutated = result["mutated"]
    original ? ["- #{original}", *("+ #{mutated}" if mutated)] : []
  end

  def crowded(counts)
    count = counts.sum
    return unless counts.any? { |each| each > GITHUB_SHOWN }
    write(
      "::notice title=Kimera::#{count} annotations; GitHub shows #{GITHUB_SHOWN} of each level per step. " \
        "The job summary and the JSON report list every finding."
    )
  end

  def sarif(document)
    write(JSON.pretty_generate(envelope(findings(document).map { |result| finding(result) })))
  end

  def findings(document) = document.fetch("results").select { |result| FINDINGS.key?(result.fetch("status")) }

  def level(result) = result["status"] == "survived" ? "error" : "warning"

  def fields(results)
    first = results.first
    column = first["column"]
    "file=#{property(first.fetch("file"))},line=#{first["line"] || 1}#{",col=#{column}" if column}" \
      ",title=#{property(title(results))}"
  end

  def title(results) = "Kimera: #{results.size} #{FINDINGS.fetch(results.first["status"])} mutant(s)"

  def envelope(results)
    { "$schema" => "https://json.schemastore.org/sarif-2.1.0.json", "version" => "2.1.0" }
      .merge("runs" => [{ "tool" => { "driver" => { "name" => "Kimera" } }, "results" => results }])
  end

  def finding(result)
    { "ruleId" => "kimera/#{result["operator"] || result["status"]}", "level" => level(result) }
      .merge("message" => { "text" => described([result]) }, "locations" => [location(result)])
  end

  def location(result)
    region = { "startLine" => result["line"] || 1, "startColumn" => result["column"] }
      .merge("endLine" => result["end_line"], "endColumn" => result["end_column"]&.+(1)).compact
    { "physicalLocation" => { "artifactLocation" => { "uri" => result["file"] }, "region" => region } }
  end

  def message(result)
    location = [result["file"], result["line"]].compact.join(":")
    "#{result["status"]} mutant ##{result["mutant_id"]} at #{location}: #{result["label"] || result["detail"]}".strip +
      noted(result["note"])
  end

  def noted(note) = note ? " (#{note})" : ""

  def property(value) = value.to_s.gsub(/[%\r\n,:]/) { |char| "%#{char.ord.to_s(16).upcase.rjust(2, "0")}" }

  def escaped(value) = value.to_s.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")

  def write(text) = @io.puts(text)
end
