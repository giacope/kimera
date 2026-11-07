# frozen_string_literal: true

require "digest"
require_relative "mutation_point"

class Kimera::MutantKeys
  ORDINAL = /\A\d+\z/
  LINE = /:\d+:(?=\h{8}\z)/

  class Fingerprint
    def initialize(row, mutant)
      @row = row
      @mutant = mutant
    end

    def key(repeat) = "#{row["file"]}:#{row.dig("location", "start_line")}:#{digest(repeat)}"

    def facts = [*row.values_at("file", "method_name", "operator"), row["original_source"].split.join(" "), mutant.to_s]
    private
    def digest(repeat) = Digest::SHA256.hexdigest([*facts, repeat].join("\n"))[0, 8]

    attr_reader :row, :mutant
  end

  def self.of(registry)
    repeats = Hash.new(0)
    new(
      registry.each.to_h do |mutant, point|
        fingerprint = Fingerprint.new(point.to_h, mutant)
        [mutant.to_i, fingerprint.key(repeats[fingerprint.facts] += 1)]
      end
    )
  end

  def initialize(keys)
    @keys = keys
  end

  def [](id) = @keys[id]

  def id(token)
    text = token.to_s
    text.match?(ORDINAL) ? text.to_i : @keys.key(text) || moved(text)
  end

  private

  def moved(text)
    found = @keys.select { |_id, key| unlined(key) == unlined(text) }.keys
    found.one? ? found.fetch(0) : text
  end

  def unlined(key) = key.sub(LINE, ":")
end
