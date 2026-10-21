# frozen_string_literal: true

require "yaml"
require_relative "../error"

module Kimera
  class Config
    DEFAULT_PATH = ".kimera.yml"

    SCALAR_KEYS = %w[framework source_root soft_timeout hard_timeout
      jobs max_survivors max_ignored max_errors coverage isolate_db
      fail_on_no_coverage count_no_coverage progress color quiet verbose log format report baseline rejudge
      relative_timeout timeout_factor timeout_slack attribution unit_tests seed flaky_runs test_quality
      judge_isolated_only confirm_survivors].freeze
    LIST_KEYS = %w[
      paths tests operators exclude exclude_tests exclude_test_names isolate_when_covered_by require load_path
    ].freeze

    SCOPE_KEYS = %i[paths operators exclude].freeze
    ATTRIBUTIONS = %w[any unit].freeze

    Precedence =
      Data.define(:cli, :configured) do
        def chosen(default)
          given = Array(cli)
          picked = given.empty? ? Array(configured) : given
          picked.empty? ? default.dup : picked
        end
      end

    Attribution =
      Data.define(:options) do
        def mode
          mode = String(options[:attribution] || "any")
          return mode if ATTRIBUTIONS.include?(mode)
          raise(UsageError, "unknown attribution #{mode.inspect} (choose: #{ATTRIBUTIONS.join(", ")})")
        end

        def settings = { attribution: mode, unit_tests: rules }

        def rules
          given = Array(options[:cli_unit_tests])
          return given.to_h { |text| pair(text) } unless given.empty?
          Hash(options[:unit_tests]).to_h { |source, patterns| [String(source), Array(patterns).map(&:to_s)] }
        end
        private
        def pair(text)
          source, pattern = String(text).split("=", 2)
          return [source, [pattern]] if pattern && !source.empty? && !pattern.empty?
          raise(UsageError, "--unit-tests takes SOURCE_GLOB=TEST_PATTERN, got #{text.inspect}")
        end
      end

    Ignores =
      Data.define(:options) do
        def rules
          local = Array(options[:ignore])
          options[:baseline] ? local + Array(options[:baseline_ignore]) : local
        end
      end

    def self.parse(argv)
      index = argv.index("--config")
      return new(File.join(".", DEFAULT_PATH)) unless index
      file = argv[index + 1]
      raise(UsageError, "no such config file: #{file}") unless file && File.exist?(file)
      new(file)
    end

    def initialize(file)
      @file = file
    end

    def options
      return {} unless File.exist?(@file)
      options = normalize(YAML.safe_load_file(@file) || {})
      baseline = options[:baseline]
      baseline ? options.merge(baseline_ignore: ignores_from(baseline)) : options
    end

    def scope(defaults) = defaults.merge(options.slice(*SCOPE_KEYS))

    private

    def normalize(data)
      options = scalars(data)
      options[:ignore] = Array(data["ignore"]).map { |r| validate(symbolize(r)) } if data.key?("ignore")
      options
    end

    def ignores_from(baseline)
      anchored = File.expand_path(baseline, File.dirname(@file))
      raise(UsageError, "no such baseline file: #{anchored}") unless File.file?(anchored)
      Array((YAML.safe_load_file(anchored) || {})["ignore"]).map { |rule| validate(symbolize(rule)) }
    end

    def scalars(data)
      (SCALAR_KEYS + LIST_KEYS).each_with_object({}) do |key, options|
        next unless data.key?(key)
        value = data[key]
        options[key.to_sym] = LIST_KEYS.include?(key) ? Array(value) : value
      end
    end

    def symbolize(rule)
      rule.transform_keys(&:to_sym)
    end

    def validate(rule)
      file = rule[:file]
      raise(UsageError, "ignore entry missing file: #{rule.inspect}") unless file
      reason(rule, file)
      rule
    end

    def reason(rule, file)
      return unless reasonless?(rule)
      raise(UsageError, "ignore entry for #{file} needs a reason: (why is this mutant equivalent?)")
    end

    def reasonless?(rule)
      rule[:reason].to_s.strip.empty?
    end
  end
end
