# frozen_string_literal: true

require "json"
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
  RELATIVE = %r{\bpath:?\s*\(?\s*["'](?!/|~)}
  REMOTES = /^PATH\n  remote: (.+)$/

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
    return [env, argv] unless File.file?(File.join(mirror, "Gemfile"))
    env["BUNDLE_GEMFILE"] = gemfile(mirror)
    [env, ["bundle", "exec", *argv]]
  end

  def gemfile(mirror)
    own = File.join(@root || mirror, "Gemfile")
    File.file?(own) && outward?(own) ? own : File.join(mirror, "Gemfile")
  end

  def outward?(gemfile)
    lock = "#{gemfile}.lock"
    return read(gemfile).match?(RELATIVE) unless File.file?(lock)
    home = File.expand_path(File.dirname(gemfile))
    read(lock).scan(REMOTES).flatten.any? { |remote| escapes?(remote, home) }
  end

  def escapes?(remote, home)
    path = File.expand_path(remote, home)
    !remote.start_with?("/") && path != home && !path.start_with?("#{home}/")
  end

  def read(path) = File.read(path, encoding: Encoding::UTF_8).scrub

  def minitest?
    @framework.to_s == "minitest"
  end
end
