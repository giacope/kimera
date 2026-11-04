# frozen_string_literal: true

require "json"
require_relative "bundle"
require_relative "parallel_databases"
require_relative "suite_env"
require_relative "../frameworks/load_path"

module Kimera
  module Execution
  end
end

class Kimera::Execution::IsolatedPlan; end

class Kimera::Execution::IsolatedPlan::ChildCommand
  CHILD = File.expand_path("isolated_child.rb", __dir__)
  MINITEST_CHILD = File.expand_path("isolated_child_minitest.rb", __dir__)
  PULSE = ".pulse"

  def initialize(framework:, test_files:, root:, seed: nil)
    @framework = framework
    @test_files = test_files
    @root = root
    @seed = seed
  end

  def command(mirror, request, ledger:, paths:)
    File.write(request_path(ledger), JSON.generate(request))
    includes = paths.flat_map { |path| ["-I", path] }
    helpers = Kimera::Frameworks::LoadPath.new(@test_files, root: mirror).flags
    ruby = ["ruby", *request["warnings"], *includes, *helpers, *argv(ledger)]
    bundled(mirror, environment(request["slot"]), ruby)
  end

  def request(locations, first: false, slot: nil, warnings: [])
    { "tests" => locations, "files" => @test_files, "first_failure" => first }
      .merge({ "seed" => @seed, "slot" => slot }.compact)
      .merge(warnings.empty? ? {} : { "warnings" => warnings })
  end

  private

  def argv(ledger)
    [minitest? ? MINITEST_CHILD : CHILD, ledger, request_path(ledger), "#{ledger}#{PULSE}"]
  end

  def request_path(ledger) = "#{ledger}.request"

  def environment(slot, suite_env = Kimera::Execution::SuiteEnv.new, databases = Kimera::Execution::ParallelDatabases.new)
    suite_env.to_h.merge(slot ? databases.numbered(slot) : {})
  end

  def bundled(mirror, env, argv)
    gemfile = Kimera::Execution::Bundle.new(@root).gemfile(mirror)
    gemfile ? [env.merge("BUNDLE_GEMFILE" => gemfile), ["bundle", "exec", *argv]] : [env, argv]
  end

  def minitest?
    @framework.to_s == "minitest"
  end
end
