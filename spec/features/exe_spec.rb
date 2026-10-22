# frozen_string_literal: true

require "bundler"
require "open3"

# The checkout executable must not activate global gems before the Gemfile resolves.
RSpec.describe("exe/kimera") do
  # Runs exe/kimera with the arguments outside the current bundle; its output and status.
  def unbundled(*arguments, **)
    command = [Gem.ruby, File.expand_path("../../exe/kimera", __dir__), *arguments]
    Bundler.with_unbundled_env { Open3.capture2e(*command, **) }
  end

  it "activates the checkout bundle before running a mutation", :aggregate_failures do
    output, status = unbundled(
      "run", "--no-gate", "--no-progress", "--tests", "examples/sample_app/spec/**/*_spec.rb",
      "--focus", "3", "examples/sample_app/app"
    )
    expect(status).to(be_success, output)
    expect(output).to(include("mutants=1", "survived=1"))
    expect(output).not_to(include("Gem::ConflictError", "diff-lcs-2.0.0 conflicts"))
  end

  it "explains how to install into a project whose Gemfile lacks kimera", :aggregate_failures do
    test_tree("Gemfile" => "source \"https://rubygems.org\"\n") do |dir|
      output, status = unbundled("run", chdir: dir)
      expect([status.exitstatus, output])
        .to(match([1, include("kimera is not in this project's Gemfile", "bundle exec kimera")]))
      expect(output).not_to(include("from "))
    end
  end
end
