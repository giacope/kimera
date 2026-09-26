# frozen_string_literal: true

require "English"
require "fileutils"
require "json"
require "shellwords"
require "tmpdir"

module KimeraSubprocess
  def test_repo_root
    File.expand_path("../..", __dir__)
  end

  def test_sample
    File.join(test_repo_root, "examples", "sample_app")
  end

  # Yields [combined output, parsed report or nil, exit status].
  def test_run(cwd:, args: [], tests: "spec/**/*_spec.rb", report: "report.json")
    Dir.mktmpdir("kimera-run") do |dir|
      json = File.join(dir, report)
      yield(
        test_output(cwd, json, tests, args),
        (File.exist?(json) ? JSON.parse(File.read(json)) : nil),
        $CHILD_STATUS.exitstatus
      )
    end
  end

  private

  def test_output(cwd, json, tests, args)
    `cd #{cwd.shellescape} && BUNDLE_GEMFILE=#{test_gemfile} #{test_command(json, tests, args)} 2>&1`
  end

  def test_gemfile
    File.join(test_repo_root, "Gemfile").shellescape
  end

  def test_command(json, tests, args)
    [
      "bundle", "exec", "ruby", "-I", File.join(test_repo_root, "lib"),
      File.join(test_repo_root, "exe", "kimera"), "run", "app",
      "--tests", tests, "--source-root", ".",
      "--report", json, *args
    ].shelljoin
  end
end

RSpec.configure do |config|
  config.include(KimeraSubprocess, type: :integration)
  config.define_derived_metadata(file_path: %r{/spec/integration/}) do |meta|
    meta[:type] = :integration
  end
end
