# frozen_string_literal: true

module Kimera
  module IgnoreList
    Match =
      Data.define(:point, :mutant) do
        def rule?(rule)
          glob = rule[:file]
          glob && File.fnmatch?(glob, point.file, File::FNM_PATHNAME) && anchors?(rule)
        end
        private
        def line?(value) = point.location.range.include?(Integer(value))
        def column?(value) = point.location.start_column == Integer(value)
        def label?(value) = value == mutant.label
        def method?(value) = value.to_s == point.method_name
        def original?(value) = squeeze(value) == squeeze(point.original_source)
        def squeeze(source) = source.to_s.split.join(" ")

        def anchors?(rule)
          ANCHORS.all? do |field, matcher|
            value = rule[field]
            !value || __send__(matcher, value)
          end
        end
      end

    Resolution = Data.define(:ids, :stale, :moved)

    Shift =
      Data.define(:rule, :line) do
        def to_s = "#{rule[:file]}:#{rule[:line]} → #{line} [#{rule[:label]}]"
      end

    module_function

    def resolve(registry, rules)
      candidates = Hash.new { |cache, glob| cache[glob] = pairs(registry, glob) }
      placements = Array(rules).map { |rule| Placement.new(rule, candidates[rule[:file]]) }
      Resolution.new(
        ids: placements.flat_map(&:ids).uniq.sort,
        stale: placements.select(&:stale?).map(&:rule), moved: placements.filter_map(&:moved)
      )
    end

    def ids(registry, rules) = resolve(registry, rules).ids

    def stale(registry, rules) = resolve(registry, rules).stale

    def pairs(registry, glob)
      files = glob ? registry.files.select { |file| File.fnmatch?(glob, file, File::FNM_PATHNAME) } : []
      files.flat_map { |file| registry.at(file).flat_map { |point| point.mutants.map { |mutant| [mutant, point] } } }
    end

    ANCHORS = { line: :line?, column: :column?, label: :label? }.merge(method: :method?, original: :original?).freeze

    def match?(rule, point, mutant)
      Match.new(point, mutant).rule?(rule)
    end
  end
end

require_relative "ignore_placement"
