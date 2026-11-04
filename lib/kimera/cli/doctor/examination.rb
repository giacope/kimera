# frozen_string_literal: true

require_relative "../../scope/config"
require_relative "../../scope/file_set"
require_relative "../coverage_minimum"
require_relative "../rails_layout"
require_relative "../rspec_options"
require_relative "../test_command"
require_relative "../test_definitions"

class Kimera::CLI::Doctor; end

class Kimera::CLI::Doctor::Examination
  FRAMEWORK_FEATURES = { "rspec" => "rspec/core", "minitest" => "minitest" }.freeze

  HELPERS = %w[.simplecov {spec,test}/**/*helper*.rb].freeze
  UNCHECKED = [["!", "Test loading: no test files to load"]].freeze

  def initialize(config, root, instruments, list)
    @config = config
    @root = root
    @instruments = instruments
    @list = list
  end

  def checks(options)
    discovery = Kimera::CLI::TestDefinitions.new(test_files).discovery
    [configuration, framework, sources, discovery, git, rails]
      .concat(notes).each { |check| shown(check) } + suite(options)
  end

  private

  def suite(options)
    return UNCHECKED.each { |check| shown(check) } if test_files.empty?
    command = test_command
    loaded = command.loading
    shown(loaded)
    options[:check_baseline] ? [loaded, *command.baselines(jobs).each { |check| shown(check) }] : [loaded]
  end

  def shown(check) = @list.shown(check)

  def configuration
    file = Kimera::Config.of(@root)
    return ["!", "Configuration: none found; run `kimera init`"] unless file.file?
    ["✓", "Configuration: #{file} (#{@config.fetch(:framework, "rspec")})"]
  end

  def framework
    name = @config.fetch(:framework, "rspec").to_s
    feature = FRAMEWORK_FEATURES.fetch(name) { return ["✗", "Framework: unknown #{name}; use rspec or minitest"] }
    return ["✓", "Framework: #{name} is installed"] if @instruments.installed?(feature)
    ["✗", "Framework: #{name} is not in this bundle; fix framework: in .kimera.yml or add it to the Gemfile"]
  end

  def sources
    count = glob(@config.fetch(:paths) { Kimera::FileSet.default.to_a }).size
    return ["✗", "Source scope: no Ruby files found; fix paths: in .kimera.yml"] if count.zero?
    ["✓", "Source scope: #{count} Ruby files"]
  end

  def git
    return ["✓", "Git: incremental runs are available"] if File.exist?(File.join(@root, ".git"))
    ["!", "Git: not a repository; `kimera changed` is unavailable"]
  end

  def rails
    return ["!", "Rails detected: verify parallel database isolation before using --jobs > 1"] if rails?
    ["✓", "Runtime: no Rails-specific parallel setup required"]
  end

  def rails? = Kimera::CLI::RailsLayout.new(@root).rails?

  def notes
    helper = glob(HELPERS).find { |path| floor?(path) }
    dotted = Kimera::CLI::RspecOptions.new(@root).loaded(test_files)
    helper ? [["!", floored(helper.delete_prefix("#{@root}/"))], *dotted] : dotted
  end

  def floored(helper)
    "Coverage floor: minimum_coverage in #{helper} can fail Kimera's partial runs; " \
      "skip it when ENV[\"KIMERA\"] is set (Kimera sets it)"
  end

  def floor?(path) = File.file?(path) && Kimera::CLI::CoverageMinimum.new(text(path)).ungated?

  def text(path) = File.read(path, encoding: Encoding::UTF_8).scrub

  def test_command
    framework = @config.fetch(:framework, "rspec").to_s
    names = Array(@config[:exclude_test_names])
    @instruments.tests(Kimera::CLI::TestExclusion.new(framework, names), test_files, @root)
  end

  def jobs = Integer(@config.fetch(:jobs, 1), exception: false).to_i

  def minitest? = @config.fetch(:framework, "rspec") == "minitest"

  def test_files
    excluded = Array(@config[:exclude_tests]).map { |pattern| File.join(@root, pattern) }
    Kimera::FileSet::Exclusion.new(excluded).without(glob(@config.fetch(:tests, tests_for)))
  end

  def tests_for = minitest? ? ["test/**/*_test.rb"] : ["spec/**/*_spec.rb"]

  def glob(patterns) = Array(patterns).flat_map { |pattern| Dir.glob(File.join(@root, pattern)).sort }.uniq
end
