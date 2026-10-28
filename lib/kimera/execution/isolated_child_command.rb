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

  def initialize(framework:, test_files:, root: nil, seed: nil)
    @framework = framework
    @test_files = test_files
    @root = root
    @seed = seed
  end

  def command(mirror, request, ledger:, paths:)
    File.write(request_path(ledger), JSON.generate(request))
    includes = paths.flat_map { |path| ["-I", path] }
    ruby = ["ruby", *request["warnings"], *includes, *helpers(mirror), *argv(ledger)]
    bundled(mirror, environment(request["slot"]), ruby)
  end

  def argv(ledger)
    [minitest? ? MINITEST_CHILD : CHILD, ledger, request_path(ledger), "#{ledger}#{PULSE}"]
  end

  def request(locations, first: false, slot: nil, warnings: [])
    { "tests" => locations, "files" => @test_files, "first_failure" => first }
      .merge(@seed ? { "seed" => @seed } : {}, slot ? { "slot" => slot } : {})
      .merge(warnings.empty? ? {} : { "warnings" => warnings })
  end

  def helpers(mirror) = Kimera::Frameworks::LoadPath.new(@test_files, root: mirror).flags

  def request_path(ledger) = "#{ledger}.request"

  private

  def environment(slot)
    env = Kimera::Execution::SUITE_ENV.dup
    slot ? env.update(Kimera::Execution::ParallelDatabases.new.numbered(slot)) : env
  end

  def bundled(mirror, env, argv)
    gemfile = Kimera::Execution::Bundle.new(@root || mirror).gemfile(mirror)
    return [env, argv] unless gemfile
    env["BUNDLE_GEMFILE"] = gemfile
    [env, ["bundle", "exec", *argv]]
  end

  def minitest?
    @framework.to_s == "minitest"
  end
end
