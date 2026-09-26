# frozen_string_literal: true

require_relative "../error"
require_relative "../scope/config"
require_relative "../scope/file_set"
require_relative "flag"
require_relative "test_command"

class Kimera::CLI::Doctor
  OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera doctor [--check-baseline]",
    flags: [
      Kimera::Flag.build("--check-baseline", :check_baseline, "Run the configured test suite and verify it is green")
    ]
  )

  FRAMEWORK_FEATURES = { "rspec" => "rspec/core", "minitest" => "minitest" }.freeze

  HELPERS = %w[.simplecov spec/spec_helper.rb spec/rails_helper.rb test/test_helper.rb].freeze

  def initialize(io: $stdout, errors: $stderr, root: ".")
    @io = io
    @errors = errors
    @root = root
  end

  def run(argv)
    options = { check_baseline: false }
    OPTIONS.parse(argv, options)
    verdict(checks(Kimera::Config.root(root: @root), options))
  rescue Kimera::UsageError => error
    usage(error)
  end

  private

  def usage(error)
    @errors.puts("kimera: #{error.message}")
    1
  end

  def checks(config, options)
    all = [configuration(config), framework(config), sources(config), tests(config), loading(config), git, rails]
    all.concat(floor)
    options[:check_baseline] ? all << baseline(config) : all
  end

  def verdict(checks)
    checks.each { |status, text| @io.puts("#{status} #{text}") }
    failed = checks.count { |status,| status == "✗" }
    return 0 if failed.zero?
    @errors.puts("kimera: doctor found #{failed} blocking issue(s)")
    1
  end

  def configuration(config)
    path = File.join(@root, Kimera::Config::DEFAULT_PATH)
    return ["!", "Configuration: none found; run `kimera init`"] unless File.file?(path)
    ["✓", "Configuration: #{Kimera::Config::DEFAULT_PATH} (#{config.fetch(:framework, "rspec")})"]
  end

  def framework(config)
    name = config.fetch(:framework, "rspec").to_s
    feature = FRAMEWORK_FEATURES.fetch(name) { return ["✗", "Framework: unknown #{name}; use rspec or minitest"] }
    return ["✓", "Framework: #{name} is installed"] if Gem.find_files(feature).any?
    ["✗", "Framework: #{name} is not in this bundle; fix framework: in .kimera.yml or add it to the Gemfile"]
  end

  def sources(config)
    count = glob(config.fetch(:paths, Kimera::FileSet::DEFAULT_GLOBS)).size
    found(count, "Source scope: #{count} Ruby files", "Source scope: no Ruby files found; fix paths: in .kimera.yml")
  end

  def tests(config)
    count = test_files(config).size
    found(count, "Test discovery: #{count} files", "Test discovery: no test files found; fix tests: in .kimera.yml")
  end

  def found(count, present, absent) = count.zero? ? ["✗", absent] : ["✓", present]

  def git
    return ["✓", "Git: incremental runs are available"] if File.exist?(File.join(@root, ".git"))
    ["!", "Git: not a repository; `kimera changed` is unavailable"]
  end

  def rails
    return ["!", "Rails detected: verify parallel database isolation before using --jobs > 1"] if rails?
    ["✓", "Runtime: no Rails-specific parallel setup required"]
  end

  def rails? = File.file?(File.join(@root, "config", "application.rb"))

  def floor
    helper = HELPERS.find { |path| floor?(File.join(@root, path)) }
    helper ? [["!", floored(helper)]] : []
  end

  def floored(helper)
    "Coverage floor: minimum_coverage in #{helper} fails partial --isolated runs; " \
      "skip it when ENV[\"KIMERA\"] is set"
  end

  def floor?(path)
    return false unless File.file?(path)
    source = File.read(path)
    source.include?("minimum_coverage") && !source.include?("KIMERA")
  end

  def baseline(config) = test_command(config).baseline

  def loading(config) = test_command(config).loading

  def test_command(config)
    Kimera::CLI::TestCommand.new(config.fetch(:framework, "rspec").to_s, test_files(config), root: @root)
  end

  def minitest?(config) = config.fetch(:framework, "rspec") == "minitest"

  def test_files(config) = glob(config.fetch(:tests, tests_for(config)))

  def tests_for(config) = minitest?(config) ? ["test/**/*_test.rb"] : ["spec/**/*_spec.rb"]

  def glob(patterns) = Array(patterns).flat_map { |pattern| Dir.glob(File.join(@root, pattern)) }.uniq
end
