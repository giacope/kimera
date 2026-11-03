# frozen_string_literal: true

require "yaml"

module KimeraEval
  TOOLCHAIN = { "BUNDLE_GEMFILE" => File.join(ROOT, "Gemfile"), "NO_COLOR" => "1" }.freeze
  LOADER = "Dir.glob('test/**/*_test.rb').sort.each { |f| require File.expand_path(f) }"
  MINITEST = ["bundle", "exec", "ruby", "-Itest", "-e", LOADER].freeze
  RSPEC = %w[bundle exec rspec].freeze
  COUNTS = /(\d+) examples?, (\d+) failures?/

  class Specs
    def initialize(exit, printed, usage)
      @exit = exit
      @printed = printed
      @usage = usage
    end

    def to_h
      examples, failures = @printed.to_s.scan(COUNTS).last
      { "ok" => @exit.ok?, "examples" => examples.to_i, "failures" => failures.to_i }.merge(@usage.timed(1))
    end
  end

  class Case
    TOTALS = %w[mutants agree false_survived false_killed abstained unbakeable].freeze

    def initialize(checkout, sandbox, selection)
      @checkout = checkout
      @sandbox = sandbox
      @selection = selection
    end

    private

    attr_reader :checkout, :sandbox

    def quick? = @selection.quick?

    def fixture(*parts) = File.join(FIXTURES, *parts)

    def shell(dir, **) = Shell.new(chdir: dir, **)

    def framework(dir)
      config = File.join(dir, ".kimera.yml")
      File.exist?(config) ? YAML.safe_load_file(config).fetch("framework", "rspec") : "rspec"
    end

    def command(dir) = framework(dir) == "minitest" ? MINITEST : RSPEC

    def oracle(dir, suite = Oracle::Suite.new(command(dir), TOOLCHAIN))
      Oracle.new(dir, suite: suite, sandbox: sandbox).tap(&:baseline!)
    end

    def target(dir, arguments: [], env: {}) = Differential::Target.new(dir, arguments, env)

    def differential(target, modes, truth)
      modes.to_h do |mode|
        [mode.join(" "), Differential.new(checkout, target.copied(sandbox), oracle: truth).call(mode)]
      end
    end

    def totals(runs)
      errors = runs.count { |run| run["error"] }
      TOTALS.to_h { |key| [key, runs.sum { |run| run.fetch(key, 0) }] }.merge("errors" => errors)
    end

    def headline(total)
      total.slice("mutants", "false_survived", "false_killed", "abstained").merge(Differential::Agreement.new(total).to_h)
    end

    def specs(...) = Specs.new(...).to_h
  end
end

Dir[File.join(__dir__, "cases", "*.rb")].each { |file| require file }

module KimeraEval
  CASES = Case.subclasses.flat_map { |kind| [kind, *kind.subclasses] }
    .sort_by { |kind| [kind::ID[0], Integer(kind::ID[1..])] }.freeze
end
