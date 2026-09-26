# frozen_string_literal: true

require_relative "suite_env"

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedPlan; end

class Kimera::Execution::IsolatedPlan::ChildCommand
  CHILD = File.expand_path("isolated_child.rb", __dir__)
  MINITEST_CHILD = File.expand_path("isolated_child_minitest.rb", __dir__)

  def initialize(framework:, test_files:)
    @framework = framework
    @test_files = test_files
  end

  def command(mirror, locations, ledger:, paths:)
    includes = paths.flat_map { |path| ["-I", path] }
    bundled(mirror, Kimera::Execution::SUITE_ENV.dup, ["ruby", *includes, "-I", helpers, *argv(locations, ledger)])
  end

  def argv(locations, ledger)
    return [CHILD, ledger, *locations] unless minitest?
    [MINITEST_CHILD, ledger, *@test_files, "--", *locations]
  end

  def helpers
    minitest? ? "test" : "spec"
  end

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
