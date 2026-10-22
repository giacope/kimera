# frozen_string_literal: true

require "English"
require "fileutils"
require "json"
require "shellwords"
require "tmpdir"

module KimeraSubprocess
  def test_repository_root
    File.expand_path("../..", __dir__)
  end

  def test_sample
    File.join(test_repository_root, "examples", "sample_app")
  end

  # Yields [combined output, parsed report or nil, exit status].
  def test_run(cwd:, arguments: [], tests: "spec/**/*_spec.rb", report: "report.json")
    Dir.mktmpdir("kimera-run") do |dir|
      json = File.join(dir, report)
      yield(
        test_output(cwd, json, tests, arguments),
        (File.exist?(json) ? JSON.parse(File.read(json, encoding: Encoding::UTF_8)) : nil),
        $CHILD_STATUS.exitstatus
      )
    end
  end

  # A kimera run's combined output, parsed report (nil when it wrote none), and exit status.
  Outcome =
    Data.define(:output, :report, :status) do
      def results = report ? report.fetch("results") : []

      def counts = report ? report.fetch("counts") : {}

      # Each mutant's status, by id.
      def verdicts = results.to_h { |row| [row["mutant_id"], row["status"]] }

      # The distinct statuses of the results for a file, or for every file.
      def statuses(file = nil)
        results.select { |row| file.nil? || row["file"] == file }.map { |row| row["status"] }.uniq
      end
    end

  # Runs kimera as test_run does, answering its Outcome.
  def test_outcome(cwd:, **) = test_run(cwd: cwd, **) { |output, report, status| Outcome.new(output, report, status) }

  # Yields a scratch directory holding the files.
  def test_tree(files, prefix = "kimera-feature")
    Dir.mktmpdir(prefix) do |root|
      files.each do |path, body|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), body)
      end
      yield(root)
    end
  end

  private

  def test_output(cwd, json, tests, arguments)
    `cd #{cwd.shellescape} && BUNDLE_GEMFILE=#{test_gemfile} #{test_command(json, tests, arguments)} 2>&1`
      .force_encoding(Encoding::UTF_8)
  end

  def test_gemfile
    File.join(test_repository_root, "Gemfile").shellescape
  end

  def test_command(json, tests, arguments)
    [
      "bundle", "exec", "ruby", "-I", File.join(test_repository_root, "lib"),
      File.join(test_repository_root, "exe", "kimera"), "run", "app",
      "--tests", tests, "--source-root", ".",
      "--report", json, *arguments
    ].shelljoin
  end
end

RSpec.configure do |config|
  config.include(KimeraSubprocess, type: :feature)
  config.define_derived_metadata(file_path: %r{/spec/features/}) do |meta|
    meta[:type] = :feature
  end
end
