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

    module_function

    def ids(registry, rules)
      rules = Array(rules)
      registry.each.filter_map { |mutant, point| mutant.id if rules.any? { |rule| match?(rule, point, mutant) } }
    end

    def stale(registry, rules)
      Array(rules).select do |rule|
        relevant?(rule, registry) && !any?(rule, registry)
      end
    end

    def relevant?(rule, registry)
      glob = rule[:file]
      glob && registry.files.any? { |file| File.fnmatch?(glob, file, File::FNM_PATHNAME) }
    end

    def any?(rule, registry)
      registry.each.any? { |mutant, point| match?(rule, point, mutant) }
    end

    ANCHORS = { line: :line?, column: :column?, label: :label? }.merge(method: :method?, original: :original?).freeze

    def match?(rule, point, mutant)
      Match.new(point, mutant).rule?(rule)
    end
  end
end
