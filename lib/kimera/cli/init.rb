# frozen_string_literal: true

require "etc"
require "yaml"
require_relative "../error"
require_relative "../scope/config"
require_relative "../scope/file_set"
require_relative "flag"

class Kimera::CLI::Init
  OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera init [options]",
    flags: [
      Kimera::FORCE_FLAG.with(help: "Replace an existing .kimera.yml"),
      Kimera::Flag.build("--dry-run", :dry_run, "Print the detected configuration without writing it")
    ]
  )

  HELPERS = %w[spec/spec_helper.rb spec/rails_helper.rb spec/helper.rb test/test_helper.rb test/helper.rb].freeze
  AGENT_POINTER = "Mutation testing: before running kimera or triaging its results, read `bundle exec kimera skill`.\n"

  def initialize(io: $stdout, errors: $stderr, root: ".")
    @io = io
    @errors = errors
    @root = root
  end

  def run(argv)
    options = { force: false, dry_run: false }
    OPTIONS.parse(argv, options)
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
    @io.write(YAML.dump(detected))
    0
  end

  def write(options)
    path = File.join(@root, Kimera::Config::DEFAULT_PATH)
    overwrite(path) if File.exist?(path) && !options[:force]
    File.write(path, YAML.dump(detected))
    announce(*signpost)
  end

  def overwrite(path) = raise(Kimera::UsageError, "#{path} already exists (use --force to replace it)")

  def signpost
    path = File.join(@root, "AGENTS.md")
    existing = File.file?(path) ? File.read(path) : ""
    return [] if existing.include?("kimera skill")
    File.write(path, pointed(existing))
    ["Pointed AI agents to `kimera skill` in AGENTS.md."]
  end

  def pointed(text) = [text.rstrip, AGENT_POINTER].reject(&:empty?).join("\n\n")

  def announce(*notes)
    @io.puts("Created #{Kimera::Config::DEFAULT_PATH} for #{framework}.", *notes, "Next: kimera doctor")
    0
  end

  def detected
    Kimera::Config.document(
      framework: framework, paths: sources, tests: tests,
      jobs: [Etc.nprocessors, 8].min, max_survivors: 0, max_errors: 0, fail_on_no_coverage: false
    )
  end

  def framework = @_framework ||= declared || layout

  def declared
    return "rspec" if File.file?(File.join(@root, ".rspec"))
    helper = HELPERS.map { |path| File.join(@root, path) }.find { |path| File.file?(path) }
    helper && framework_named_in(File.read(helper))
  end

  def framework_named_in(text)
    return "rspec" if text.match?(/\bRSpec\b|require\s*\(?\s*["']rspec/)
    "minitest" if text.match?(/minitest/i)
  end

  def layout
    File.directory?(File.join(@root, "test")) && !File.directory?(File.join(@root, "spec")) ? "minitest" : "rspec"
  end

  def sources
    paths = %w[app/**/*.rb lib/**/*.rb].select { |glob| Dir.glob(File.join(@root, glob)).any? }
    paths.empty? ? Kimera::FileSet::DEFAULT_GLOBS : paths
  end

  def tests
    globs = framework == "minitest" ? %w[test/**/*_test.rb spec/**/*_spec.rb] : %w[spec/**/*_spec.rb]
    [globs.find { |glob| Dir.glob(File.join(@root, glob)).any? } || globs.first]
  end
end
