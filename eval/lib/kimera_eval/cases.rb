# frozen_string_literal: true

require "yaml"

module KimeraEval
  TOOLCHAIN = { "BUNDLE_GEMFILE" => File.join(ROOT, "Gemfile"), "NO_COLOR" => "1" }.freeze
  LOADER = "Dir.glob('test/**/*_test.rb').sort.each { |f| require File.expand_path(f) }"
  MINITEST = ["bundle", "exec", "ruby", "-Itest", "-e", LOADER].freeze
  RSPEC = %w[bundle exec rspec].freeze
  COUNTS = /(\d+) examples?, (\d+) failures?/

  # What bin/spec reported.
  Specs =
    Data.define(:ok, :examples, :failures, :wall_s) do
      def self.of(result)
        examples, failures = result.stdout.scan(COUNTS).last
        new(result.ok?, examples.to_i, failures.to_i, result.wall.round(1))
      end

      def to_h = super.transform_keys(&:to_s)
    end

  # What every case gets: the checkout under evaluation, a sandbox for
  # copies, and the run's settings.
  Context = Data.define(:checkout, :sandbox, :settings)

  # A case measures one gap. #call returns a metrics hash with "pass".
  class Case
    TOTALS = %w[mutants agree false_survived false_killed abstained unbakeable].freeze

    def initialize(context)
      @context = context
    end

    private

    attr_reader :context

    def checkout = context.checkout

    def sandbox = context.sandbox

    def quick? = context.settings.quick

    def fixture(*parts) = File.join(FIXTURES, *parts)

    def framework(dir)
      config = File.join(dir, ".kimera.yml")
      File.exist?(config) ? YAML.safe_load_file(config).fetch("framework", "rspec") : "rspec"
    end

    def command(dir) = framework(dir) == "minitest" ? MINITEST : RSPEC

    def oracle(dir, runner = Oracle::Runner.new(command(dir), TOOLCHAIN))
      Oracle.new(dir, runner: runner, sandbox: sandbox).tap(&:baseline!)
    end

    def target(dir, arguments: [], env: {}) = Differential::Target.new(dir, arguments, env)

    def differential(target, modes, truth = oracle(target.project))
      modes.to_h { |mode| [mode.join(" "), Differential.new(checkout, copied(target), oracle: truth).call(mode)] }
    end

    def copied(target) = target.with(project: sandbox.copy(target.project))

    def totals(runs)
      errors = runs.count { |run| run["error"] }
      TOTALS.to_h { |key| [key, runs.sum { |run| run.fetch(key, 0) }] }.merge("errors" => errors)
    end

    def headline(total)
      agreement = Scoring.agreement(total.slice(*Differential::VERDICTS))
      total.slice("mutants", "false_survived", "false_killed", "abstained").merge("agreement_pct" => agreement)
    end

    def specs(result) = Specs.of(result).to_h
  end
end

Dir[File.join(__dir__, "cases", "*.rb")].each { |file| require file }

module KimeraEval
  CASES = Case.subclasses.sort_by { |kind| [kind::ID[0], Integer(kind::ID[1..])] }.freeze
end
