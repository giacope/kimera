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
