# frozen_string_literal: true

require "etc"
require_relative "../error"
require_relative "../operators"
require_relative "../scope/config"
require_relative "../scope/file_set"
require_relative "config_template"
require_relative "flag"
require_relative "rails_layout"
require_relative "rspec_options"
require_relative "test_definitions"

class Kimera::CLI::Init
  OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera init [options]",
    flags: [
      Kimera::Flag.build("--force", :force, "Replace an existing .kimera.yml"),
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
  FURTHER = [Kimera::Operators::WhenClause, Kimera::Operators::AppendDeletion].freeze
  MINITEST = %r{minitest/autorun|Minitest::Test|ActiveSupport::TestCase}
  LOCKS = %w[Gemfile.lock gems.locked].freeze
  LOCKED = { "rspec" => /^    rspec-core \(/, "minitest" => /^    minitest \(/ }.freeze
  DOCUMENT = ->(**fields) { fields.transform_keys(&:to_s) }

  def initialize(io: $stdout, errors: $stderr, root: ".", processors: Etc.nprocessors)
    @io = io
    @errors = errors
    @root = root
    @processors = processors
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
    config = Kimera::Config.of(@root)
    config.create(options[:force]) { template }
    announce(config)
  end

  def template = Kimera::CLI::ConfigTemplate.new(detected).render

  def announce(config)
    @io.puts("Created #{config} for #{framework}.", "Next: kimera doctor")
    0
  end

  def detected
    DOCUMENT.call(
      framework: framework, paths: sources, tests: tests, **left_out, operators: operators,
      jobs: [@processors, JOBS].min, max_survivors: 0, max_errors: 0, count_no_coverage: true
    )
  end

  def left_out
    present = BROWSER_TESTS.fetch(framework, []).select { |glob| rails_app? && Dir.glob(File.join(@root, glob)).any? }
    [*present, *Kimera::CLI::RspecOptions.new(@root).excluded].then { |left| left.empty? ? {} : { exclude_tests: left } }
  end

  def rails_app? = Kimera::CLI::RailsLayout.new(@root).rails?

  def operators = [*Kimera::Operators.build.map(&:key), *FURTHER.map { it.new.key }, *("rails" if rails_app?)]

  def framework = @_framework ||= declared.fetch(0) { bundled.fetch(0) { layout } }

  def declared
    return ["rspec"] if File.file?(File.join(@root, ".rspec"))
    return ["minitest"] if minitest_only?
    present(HELPERS).flat_map { |helper| framework_named_in(File.read(helper, encoding: Encoding::UTF_8).scrub) }
  end

  def minitest_only?
    return false if File.directory?(File.join(@root, "spec"))
    Dir.glob(File.join(@root, "test", "**", "*.rb")).first(200).any? { |path| text(path).match?(MINITEST) }
  end

  def text(path) = File.read(path, encoding: Encoding::UTF_8).scrub

  def framework_named_in(text)
    return ["minitest"] if text.match?(MINITEST)
    return ["rspec"] if text.match?(/\bRSpec\b|require\s*\(?\s*["']rspec/)
    text.match?(/minitest/i) ? ["minitest"] : []
  end

  def bundled
    present(LOCKS).flat_map do |lock|
      text = File.read(lock, encoding: Encoding::UTF_8).scrub
      found = LOCKED.select { |_name, line| text.match?(line) }.keys
      found.one? ? found : []
    end
  end

  def present(names) = names.lazy.map { |name| File.join(@root, name) }.select { |path| File.file?(path) }.first(1)

  def layout
    File.directory?(File.join(@root, "test")) && !File.directory?(File.join(@root, "spec")) ? "minitest" : "rspec"
  end

  def sources
    paths = %w[app/**/*.rb lib/**/*.rb].select { |glob| Dir.glob(File.join(@root, glob)).any? }
    paths.empty? ? Kimera::FileSet.default.to_a : paths
  end

  def tests
    globs = framework == "minitest" ? MINITEST_GLOBS : %w[spec/**/*_spec.rb]
    found = globs.each_with_index.max_by { |glob, index| [*reach(glob), -index] }.first
    Kimera::CLI::RspecOptions.new(@root).tests([found])
  end

  def reach(glob) = Kimera::CLI::TestDefinitions.within(@root, glob).reach
end
