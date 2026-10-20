# frozen_string_literal: true

module Kimera
  class IgnoreList
    Match =
      Data.define(:point, :mutant) do
        def rule?(rule)
          ANCHORS.all? do |field, matcher|
            value = rule[field]
            !value || __send__(matcher, value)
          end
        end
        private
        def line?(value) = point.location.range.include?(Integer(value))
        def starts?(value) = point.location.start_line == Integer(value)
        def operator?(value) = Array(value).map(&:to_s).include?(point.operator)
        def column?(value) = point.location.start_column + 1 == Integer(value)
        def label?(value) = value == mutant.label
        def method?(value) = value.to_s == point.method_name
        def original?(value) = squeeze(value) == squeeze(point.original_source)
        def squeeze(source) = source.to_s.split.join(" ")
      end

    Resolution = Data.define(:ids, :stale, :moved)

    Shift =
      Data.define(:rule, :line) do
        def to_s = "#{rule[:file]}:#{rule[:line]} → #{line} [#{rule[:label]}]"
      end

    ANCHORS = { line: :line?, column: :column?, label: :label? }.merge(method: :method?, original: :original?)
      .merge(starts: :starts?, operator: :operator?).freeze

    def initialize(rules)
      @rules = rules
    end

    def resolve(registry)
      placements = placed(registry)
      kept = uncontested(placements)
      Resolution.new(
        ids: kept.flat_map(&:ids).uniq.sort, stale: lapsed(placements, kept),
        moved: kept.filter_map(&:moved)
      )
    end

    def ids(registry) = resolve(registry).ids

    def stale(registry) = resolve(registry).stale

    private

    def placed(registry)
      candidates = Hash.new { |cache, glob| cache[glob] = pairs(registry, glob) }
      Array(@rules).map { |rule| Placement.new(rule, candidates[rule[:file]]) }
    end

    def uncontested(placements)
      claimed = placements.flat_map(&:ids).tally.select { |_id, count| count > 1 }.keys
      placements.reject { |placement| placement.contested?(claimed) }
    end

    def lapsed(placements, kept)
      placements.select { |placement| placement.stale? || !kept.include?(placement) }.map(&:rule)
    end

    def pairs(registry, glob)
      files = glob ? registry.files.select { |file| File.fnmatch?(glob, file, File::FNM_PATHNAME) } : []
      files.flat_map { |file| registry.at(file).flat_map { |point| point.mutants.map { |mutant| [mutant, point] } } }
    end
  end
end

require_relative "ignore_placement"
