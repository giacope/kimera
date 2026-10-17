# frozen_string_literal: true

require "yaml"
require_relative "../error"

module Kimera
  module Config
    DEFAULT_PATH = ".kimera.yml"

    SCALAR_KEYS = %w[framework source_root soft_timeout hard_timeout
      jobs max_survivors max_ignored max_errors coverage isolate_db
      fail_on_no_coverage count_no_coverage progress color quiet verbose log format report baseline rejudge
      relative_timeout timeout_factor timeout_slack attribution unit_tests seed flaky_runs test_quality].freeze
    LIST_KEYS = %w[paths tests operators exclude exclude_tests isolate_when_covered_by require].freeze

    SCOPE_KEYS = %i[paths operators exclude].freeze
    ATTRIBUTIONS = %w[any unit].freeze

    module_function

    def parse(argv)
      index = argv.index("--config")
      return root unless index
      file = argv[index + 1]
      raise(UsageError, "no such config file: #{file}") unless file && File.exist?(file)
      load(file)
    end

    def prefer(from_cli, from_config, default)
      cli = Array(from_cli)
      chosen = cli.empty? ? Array(from_config) : cli
      chosen.empty? ? default.dup : chosen
    end

    def document(**options) = options.transform_keys(&:to_s)

    def scope(defaults, argv)
      defaults.merge(parse(argv).slice(*SCOPE_KEYS))
    end

    def load(file)
      return {} unless File.exist?(file)
      options = normalize(YAML.safe_load_file(file) || {})
      baseline = options[:baseline]
      baseline ? options.merge(baseline_ignore: ignores_from(baseline, file)) : options
    end

    def ignores(options)
      local = Array(options[:ignore])
      options[:baseline] ? local + Array(options[:baseline_ignore]) : local
    end

    def root(root: ".")
      load(File.join(root, DEFAULT_PATH))
    end

    def normalize(data)
      options = scalars(data)
      options[:ignore] = Array(data["ignore"]).map { |r| validate(symbolize(r)) } if data.key?("ignore")
      options
    end

    def ignores_from(baseline, file)
      anchored = File.expand_path(baseline, File.dirname(file))
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

    def attribution(value)
      mode = String(value || "any")
      return mode if ATTRIBUTIONS.include?(mode)
      raise(UsageError, "unknown attribution #{mode.inspect} (choose: #{ATTRIBUTIONS.join(", ")})")
    end

    def unit_tests(value)
      case value
      when nil then {}
      when Hash then value.to_h { |source, patterns| [String(source), Array(patterns).map { |each| String(each) }] }
      else Array(value).to_h { |text| unit_test(text) }
      end
    end

    def unit_test(text)
      source, pattern = String(text).split("=", 2)
      return [source, [pattern]] if pattern && !source.empty? && !pattern.empty?
      raise(UsageError, "--unit-tests takes SOURCE_GLOB=TEST_PATTERN, got #{text.inspect}")
    end
  end
end
