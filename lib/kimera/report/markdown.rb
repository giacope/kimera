# frozen_string_literal: true

module Kimera
  module Report
  end
end

class Kimera::Report::Markdown
  SHOWN = 50

  def initialize(document, nouns)
    @document = document
    @nouns = nouns
  end

  def render = [heading, *table, *overflow].join("\n") << "\n"

  private

  def findings = @_findings ||= @document.fetch("results").select { |result| @nouns.key?(result.fetch("status")) }

  def counts = @document.fetch("counts").transform_keys(&:to_s)

  def heading
    survived = counts.fetch("survived")
    "### Kimera: #{survived} surviving of #{counts.fetch("total")} mutants#{scored(survived)}\n"
  end

  def scored(survived)
    if (counts.fetch("killed") + survived).positive?
      " (score #{format("%.1f%%", @document.fetch("mutation_score") * 100)})"
    else
      ""
    end
  end

  def table
    return ["Every mutant in scope was killed."] if findings.empty?
    ["| | Where | Mutation |", "|---|---|---|", *findings.first(SHOWN).map { |result| row(result) }]
  end

  def row(result)
    method = result["method"]
    where = "`#{[result["file"], result["line"]].compact.join(":")}`#{" in `#{method}`" if method}"
    "| #{@nouns.fetch(result["status"]).capitalize} | #{where} | #{change(result)} |"
  end

  def change(result)
    original = result["original"]
    label = result["label"]
    return cell(label || result["detail"]) unless original
    "`#{cell(original)}` → `#{cell(result["mutated"] || label)}`"
  end

  def cell(text) = text.to_s.gsub("|", "\\|").split.join(" ")

  def overflow
    hidden = findings.size - SHOWN
    hidden.positive? ? ["", "…and #{hidden} more; the JSON report lists every one."] : []
  end
end
