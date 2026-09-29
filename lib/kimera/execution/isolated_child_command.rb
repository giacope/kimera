# frozen_string_literal: true

require "json"
require_relative "suite_env"

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedPlan; end

class Kimera::Execution::IsolatedPlan::ChildCommand
  CHILD = File.expand_path("isolated_child.rb", __dir__)
  MINITEST_CHILD = File.expand_path("isolated_child_minitest.rb", __dir__)
  PULSE = ".pulse"

  def initialize(framework:, test_files:)
    @framework = framework
    @test_files = test_files
  end

  def command(mirror, locations, ledger:, paths:)
    File.write(request_path(ledger), JSON.generate(request(locations)))
    includes = paths.flat_map { |path| ["-I", path] }
    bundled(mirror, Kimera::Execution::SUITE_ENV.dup, ["ruby", *includes, "-I", helpers, *argv(ledger)])
  end

  def argv(ledger)
    [minitest? ? MINITEST_CHILD : CHILD, ledger, request_path(ledger), "#{ledger}#{PULSE}"]
  end

  def request(locations)
    { "tests" => locations, "files" => @test_files }
  end

  def helpers
    minitest? ? "test" : "spec"
  end

  def request_path(ledger) = "#{ledger}.request"

  private

  def bundled(mirror, env, argv)
    gemfile = File.join(mirror, "Gemfile")
    return [env, argv] unless File.file?(gemfile)
    env["BUNDLE_GEMFILE"] = gemfile
    [env, ["bundle", "exec", *argv]]
  end

  def minitest?
    @framework.to_s == "minitest"
  end
end
