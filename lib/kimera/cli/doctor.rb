# frozen_string_literal: true

require_relative "../error"
require_relative "../scope/config"
require_relative "../scope/file_set"
require_relative "checklist"
require_relative "coverage_minimum"
require_relative "flag"
require_relative "rails_layout"
require_relative "rspec_options"
require_relative "test_command"
require_relative "test_definitions"

class Kimera::CLI::Doctor
  OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera doctor [--check-baseline [--jobs N]]",
    flags: [
      Kimera::Flag.build("--check-baseline", :check_baseline, "Run the configured test suite and verify it is green"),
      Kimera::Flag.build("--jobs N", :jobs, "Also run it split across N processes (default: jobs:)", type: Integer)
    ]
  )

  FRAMEWORK_FEATURES = { "rspec" => "rspec/core", "minitest" => "minitest" }.freeze

  HELPERS = %w[.simplecov {spec,test}/**/*helper*.rb].freeze
  UNCHECKED = [["!", "Test loading: no test files to load"]].freeze

  def initialize(io: $stdout, errors: $stderr, root: ".", env: ENV)
    @io = io
    @errors = errors
    @root = root
    @env = env
  end

  def run(argv)
    _, options = OPTIONS.parse(argv, { check_baseline: false })
    config = Kimera::Config.new(File.join(@root, Kimera::Config::DEFAULT_PATH)).options.merge(options.slice(:jobs))
    expose(config)
    list.verdict(checks(config, options))
  rescue Kimera::UsageError => error
    usage(error)
  end

  private

  def expose(config, env = @env)
    env.store(Kimera::Frameworks::LoadPath::VARIABLE, Array(config[:load_path]).join(File::PATH_SEPARATOR))
  end

  def usage(error)
    @errors.puts("kimera: #{error.message}")
    1
  end

  def checks(config, options)
    discovery = Kimera::CLI::TestDefinitions.new(test_files(config)).discovery
    [configuration(config), framework(config), sources(config), discovery, git, rails]
      .concat(notes(config)).each { |check| shown(check) } + suite(config, options)
  end

  def suite(config, options)
    return UNCHECKED.each { |check| shown(check) } if test_files(config).empty?
    loaded = shown(loading(config))
    options[:check_baseline] ? [loaded, *baselines(config).each { |check| shown(check) }] : [loaded]
  end

  def list = @_list ||= Kimera::CLI::Checklist.new(@io, @errors)

  def shown(check) = list.shown(check)

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

  def notes(config)
    helper = glob(HELPERS).find { |path| floor?(path) }
    dotted = Kimera::CLI::RspecOptions.new(@root).loaded(test_files(config))
    helper ? [["!", floored(helper.delete_prefix("#{@root}/"))], *dotted] : dotted
  end

  def floored(helper)
    "Coverage floor: minimum_coverage in #{helper} can fail Kimera's partial runs; " \
      "skip it when ENV[\"KIMERA\"] is set (Kimera sets it)"
  end

  def floor?(path) = File.file?(path) && Kimera::CLI::CoverageMinimum.new(text(path)).ungated?

  def text(path) = File.read(path, encoding: Encoding::UTF_8).scrub

  def baselines(config) = test_command(config).baselines(jobs(config))

  def loading(config) = test_command(config).loading

  def test_command(config)
    framework = config.fetch(:framework, "rspec").to_s
    names = Array(config[:exclude_test_names])
    Kimera::CLI::TestCommand.new(framework, test_files(config), root: @root, names: names)
  end

  def jobs(config) = Integer(config.fetch(:jobs, 1), exception: false).to_i

  def minitest?(config) = config.fetch(:framework, "rspec") == "minitest"

  def test_files(config)
    excluded = Array(config[:exclude_tests]).map { |pattern| File.join(@root, pattern) }
    Kimera::FileSet.new([], exclude: excluded).without(glob(config.fetch(:tests, tests_for(config))))
  end

  def tests_for(config) = minitest?(config) ? ["test/**/*_test.rb"] : ["spec/**/*_spec.rb"]

  def glob(patterns) = Array(patterns).flat_map { |pattern| Dir.glob(File.join(@root, pattern)).sort }.uniq
end
