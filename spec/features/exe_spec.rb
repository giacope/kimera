# frozen_string_literal: true

require "bundler"
require "open3"
require "tmpdir"

# The checkout executable must not activate global gems before the Gemfile resolves.
RSpec.describe("exe/kimera") do
  it "activates the checkout bundle before running a mutation", :aggregate_failures do
    command = [
      Gem.ruby, File.expand_path("../../exe/kimera", __dir__), "run", "--no-gate", "--no-progress",
      "--tests", "examples/sample_app/spec/**/*_spec.rb", "--focus", "3", "examples/sample_app/app"
    ]
    output = nil
    status = nil
    Bundler.with_unbundled_env { output, status = Open3.capture2e(*command) }
    expect(status).to(be_success, output)
    expect(output).to(include("mutants=1", "survived=1"))
    expect(output).not_to(include("Gem::ConflictError", "diff-lcs-2.0.0 conflicts"))
  end

  it "explains how to install into a project whose Gemfile lacks kimera", :aggregate_failures do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "Gemfile"), "source \"https://rubygems.org\"\n")
      output = nil
      status = nil
      command = [Gem.ruby, File.expand_path("../../exe/kimera", __dir__), "run"]
      Bundler.with_unbundled_env { output, status = Open3.capture2e(*command, chdir: dir) }
      expect(status.exitstatus).to(eq(1))
      expect(output).to(include("kimera is not in this project's Gemfile", "bundle exec kimera"))
      expect(output).not_to(include("from "))
    end
  end
end
