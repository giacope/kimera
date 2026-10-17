# frozen_string_literal: true

require "digest"
require_relative "mutation_point"

class Kimera::MutantKeys
  ORDINAL = /\A\d+\z/
  LINE = /:\d+:(?=\h{8}\z)/

  Fingerprint =
    Data.define(:point, :mutant) do
      def key(repeat) = "#{point.file}:#{point.location.start_line}:#{digest(repeat)}"

      def facts = [point.file, point.method_name, point.operator, point.original_source.split.join(" "), mutant.label]
      private
      def digest(repeat) = Digest::SHA256.hexdigest([*facts, repeat].join("\n"))[0, 8]
    end

  def self.of(registry)
    repeats = Hash.new(0)
    new(
      registry.each.to_h do |mutant, point|
        fingerprint = Fingerprint.new(point, mutant)
        [mutant.id, fingerprint.key(repeats[fingerprint.facts] += 1)]
      end
    )
  end

  def initialize(keys)
    @keys = keys
  end

  def [](id) = @keys[id]

  def id(token)
    text = token.to_s
    text.match?(ORDINAL) ? text.to_i : @keys.key(text) || moved(text) || text
  end

  private

  def moved(text)
    found = @keys.select { |_id, key| unlined(key) == unlined(text) }.keys
    found.first if found.one?
  end

  def unlined(key) = key.sub(LINE, ":")
end
