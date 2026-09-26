# frozen_string_literal: true

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

  ENV_FLAG = { "KIMERA" => "1" }.freeze

  def command(mirror, locations, paths:)
    bundled(mirror, ENV_FLAG.dup, ["ruby", *paths.flat_map { |path| ["-I", path] }, "-I", helpers, *argv(locations)])
  end

  def argv(locations)
    return [CHILD, *locations] unless minitest?
    [MINITEST_CHILD, *@test_files, "--", *locations]
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
