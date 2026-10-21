# frozen_string_literal: true

require "etc"
require_relative "../error"
require_relative "../operators"
require_relative "../scope/config"
require_relative "../scope/file_set"
require_relative "config_template"
require_relative "flag"
require_relative "rails_layout"

class Kimera::CLI::Init
  OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera init [options]",
    flags: [
      Kimera::FORCE_FLAG.with(help: "Replace an existing .kimera.yml"),
      Kimera::Flag.build("--dry-run", :dry_run, "Print the detected configuration without writing it")
    ]
  )

  HELPERS = %w[spec/spec_helper.rb spec/rails_helper.rb spec/helper.rb test/test_helper.rb test/helper.rb].freeze
  MINITEST_GLOBS = %w[test/**/*_test.rb test/**/test_*.rb test/**/spec_*.rb spec/**/*_spec.rb].freeze
  BROWSER_TESTS = {
    "minitest" => %w[test/system/**/*_test.rb],
    "rspec" => %w[spec/system/**/*_spec.rb spec/features/**/*_spec.rb]
  }.freeze
  JOBS = 4
  MINITEST = %r{minitest/autorun|Minitest::Test|ActiveSupport::TestCase}
  LOCKS = %w[Gemfile.lock gems.locked].freeze
  LOCKED = { "rspec" => /^    rspec-core \(/, "minitest" => /^    minitest \(/ }.freeze
  DOCUMENT = ->(**fields) { fields.transform_keys(&:to_s) }

  def initialize(io: $stdout, errors: $stderr, root: ".")
    @io = io
    @errors = errors
    @root = root
  end

  def run(argv)
    _, options = OPTIONS.parse(argv, { force: false, dry_run: false })
    options[:dry_run] ? preview : write(options)
  rescue Kimera::UsageError => error
    usage(error)
  end

  private

  def usage(error)
    @errors.puts("kimera: #{error.message}")
    1
  end

  def preview
    @io.write(template)
    0
  end

  def write(options)
    path = File.join(@root, Kimera::Config::DEFAULT_PATH)
    overwrite(path) if File.exist?(path) && !options[:force]
    File.write(path, template)
    announce
  end

  def template = Kimera::CLI::ConfigTemplate.new(detected).render

  def overwrite(path) = raise(Kimera::UsageError, "#{path} already exists (use --force to replace it)")

  def announce
    @io.puts("Created #{Kimera::Config::DEFAULT_PATH} for #{framework}.", "Next: kimera doctor")
    0
  end

  def detected
    DOCUMENT.call(
      framework: framework, paths: sources, tests: tests, **browserless, **rails_operators,
      jobs: [Etc.nprocessors, JOBS].min, max_survivors: 0, max_errors: 0, count_no_coverage: true
    )
  end

  def browserless
    present = BROWSER_TESTS.fetch(framework, []).select { |glob| Dir.glob(File.join(@root, glob)).any? }
    rails_app? && present.any? ? { exclude_tests: present } : {}
  end

  def rails_app? = Kimera::CLI::RailsLayout.new(@root).rails?

  def rails_operators = rails_app? ? { operators: [*Kimera::Operators::DEFAULT_KEYS, "rails"] } : {}

  def framework = @_framework ||= declared || bundled || layout

  def declared
    return "rspec" if File.file?(File.join(@root, ".rspec"))
    return "minitest" if minitest_only?
    helper = present(HELPERS)
    helper && framework_named_in(File.read(helper, encoding: Encoding::UTF_8).scrub)
  end

  def minitest_only?
    return false if File.directory?(File.join(@root, "spec"))
    Dir.glob(File.join(@root, "test", "**", "*.rb")).first(200).any? { |path| text(path).match?(MINITEST) }
  end

  def text(path) = File.read(path, encoding: Encoding::UTF_8).scrub

  def framework_named_in(text)
    return "minitest" if text.match?(MINITEST)
    return "rspec" if text.match?(/\bRSpec\b|require\s*\(?\s*["']rspec/)
    "minitest" if text.match?(/minitest/i)
  end

  def bundled
    lock = present(LOCKS)
    return unless lock
    text = File.read(lock, encoding: Encoding::UTF_8).scrub
    found = LOCKED.select { |_name, line| text.match?(line) }.keys
    found.first if found.one?
  end

  def present(names) = names.map { |name| File.join(@root, name) }.find { |path| File.file?(path) }

  def layout
    File.directory?(File.join(@root, "test")) && !File.directory?(File.join(@root, "spec")) ? "minitest" : "rspec"
  end

  def sources
    paths = %w[app/**/*.rb lib/**/*.rb].select { |glob| Dir.glob(File.join(@root, glob)).any? }
    paths.empty? ? Kimera::FileSet::DEFAULT_GLOBS : paths
  end

  def tests
    globs = framework == "minitest" ? MINITEST_GLOBS : %w[spec/**/*_spec.rb]
    [globs.find { |glob| Dir.glob(File.join(@root, glob)).any? } || globs.first]
  end
end
