# frozen_string_literal: true

require "yaml"

module KimeraEval
  # What every case gets: the checkout under evaluation, a sandbox for
  # copies, and the fixed toolchain the oracles run on (this repo's bundle).
  Context =
    Data.define(:checkout, :sandbox, :options) do
      def runner_env = { "BUNDLE_GEMFILE" => File.join(ROOT, "Gemfile"), "NO_COLOR" => "1" }

      def quick? = options.fetch(:quick, false)
    end

  # A case measures one gap. #call returns a metrics hash with "pass".
  class Case
    def initialize(context)
      @context = context
    end

    private

    attr_reader :context

    def checkout = context.checkout

    def sandbox = context.sandbox

    def fixture(*parts) = File.join(FIXTURES, *parts)

    def framework(dir) = YAML.safe_load_file(File.join(dir, ".kimera.yml")).fetch("framework", "rspec")

    def oracle_command(dir)
      return ["bundle", "exec", "rspec"] unless framework(dir) == "minitest"
      ["bundle", "exec", "ruby", "-Itest", "-e", "Dir.glob('test/**/*_test.rb').sort.each { |f| require File.expand_path(f) }"]
    end

    def oracle(dir, command: oracle_command(dir), env: context.runner_env)
      Oracle.new(dir, command: command, sandbox: sandbox, env: env).tap(&:baseline!)
    end

    def differential(dir, modes, args: [], oracle: oracle(dir), env: {})
      modes.to_h do |mode|
        [mode.join(" "), Differential.new(checkout, sandbox.copy(dir), oracle: oracle, args: args, env: env).call(mode)]
      end
    end

    def totals(runs)
      keys = %w[mutants agree false_survived false_killed abstained unbakeable]
      keys.to_h { |key| [key, runs.sum { |run| run.fetch(key, 0) }] }
        .merge("errors" => runs.count { |run| run["error"] })
    end
  end
end

Dir[File.join(__dir__, "cases", "*.rb")].each { |file| require file }

module KimeraEval
  CASES = Case.subclasses.sort_by { |kind| kind::ID }.freeze
end
