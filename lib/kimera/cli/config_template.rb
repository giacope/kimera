# frozen_string_literal: true

require "json"
require "yaml"

class Kimera::CLI::ConfigTemplate
  SCHEMA = "https://raw.githubusercontent.com/giacope/kimera/main/schema/kimera.schema.json"
  HEADER = [
    "# yaml-language-server: $schema=#{SCHEMA}",
    "# Kimera configuration. Every key also has a command-line flag; flags win.",
    "# Reference: https://github.com/giacope/kimera#configuration"
  ].freeze
  PATH = File.expand_path("../../../schema/kimera.schema.json", __dir__)
  WIDTH = 78
  FOOTER = <<~YAML
    # Gate: how many mutants may be ignore-listed. Raise it only in the diff
    # that adds the entry it admits.
    # max_ignored: 0

    # Survivors accepted when adopting Kimera: kimera baseline create --write.
    # baseline: .kimera-baseline.yml

    # Known-equivalent mutants; each entry needs a reason. A comment in the
    # source does the same: # kimera:disable[-next-line] [OPERATOR ...]: REASON
    # ignore:
    #   - file: app/models/order.rb
    #     line: 42
    #     label: "> => >="
    #     reason: why no test can tell the two apart
  YAML

  def initialize(settings)
    @settings = settings
  end

  def render = [*HEADER, *@settings.map { |key, value| entry(key, value) }, "", FOOTER].join("\n")

  private

  def entry(key, value) = ["", *note(key), YAML.dump(key => value).delete_prefix("---\n").chomp].join("\n")

  def note(key) = wrap(properties.fetch(key).fetch("description")).map { |line| "# #{line}" }

  def wrap(text)
    text.split.reduce([]) do |lines, word|
      joined = "#{lines.last} #{word}"
      lines.empty? || joined.size > WIDTH ? [*lines, word] : [*lines[0...-1], joined]
    end
  end

  def properties = @_properties ||= JSON.parse(File.read(PATH)).fetch("properties")
end
