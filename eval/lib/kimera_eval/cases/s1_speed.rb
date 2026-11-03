# frozen_string_literal: true

module KimeraEval
  class SpeedCase < Case
    ID = "S1"
    TITLE = "Speed on real suites (sample_app, dry-inflector, kimera self-host subset)"
    INFLECTOR = "https://github.com/dry-rb/dry-inflector.git"
    REVISION = "b6a2819f0cf1bc0c24e024bbdf73f4f67003cbc9"
    CACHE = File.join(ROOT, "eval", "tmp", "dry-inflector")
    GEMFILE = <<~RUBY
      source "https://rubygems.org"
      gemspec path: "."
      gem "rspec", "~> 3.13"
      gem "warning"
      gem "kimera", path: ENV.fetch("KIMERA_PATH")
    RUBY
    SELF = %w[lib/kimera/operators lib/kimera/rewrite].freeze
    INFLECTED = %w[lib --tests spec/**/*_spec.rb --operators all].freeze

    def call
      runs = sample.merge(quick? ? {} : slow)
      { "pass" => runs.values.none? { |run| run["error"] }, "summary" => runs.transform_values { |run| run["wall_s"] } }
        .merge("runs" => runs)
    end

    private

    def slow = { "dry-inflector --jobs 4" => inflector, "self-host subset --jobs 4" => itself }

    def sample = [%w[--jobs 1], %w[--jobs 4]].to_h { |mode| ["sample_app #{mode.join(" ")}", timed(mode)] }

    def timed(mode)
      copy = sandbox.copy(File.join(ROOT, "examples", "sample_app"))
      exit, _, usage = checkout.cli("run", "app", "--tests", "spec/**/*_spec.rb", *mode, "--no-progress", chdir: copy)
      usage.timed(2).merge(exit.exited)
    end

    def inflector
      dir = clone
      env = { "BUNDLE_GEMFILE" => File.join(dir, "Gemfile.eval"), "KIMERA_PATH" => checkout.to_s }
      Shell.new(env: env, chdir: dir, timeout: 900).run("bundle", "install")
      judged(dir, env, oracle(dir, Oracle::Suite.new(RSPEC, env)))
    end

    def judged(dir, env, truth)
      run = differential(target(dir, arguments: INFLECTED, env: env), [%w[--jobs 4]], truth).values.first
      run.merge("disagreements" => run["disagreements"]&.first(20))
    end

    def clone
      shell(ROOT).run("git", "clone", "-q", INFLECTOR, CACHE) unless File.directory?(CACHE)
      shell(CACHE).run("git", "checkout", "-q", REVISION)
      sandbox.copy(CACHE, "dry-inflector").tap { |dir| bundled(dir) }
    end

    def bundled(dir)
      FileUtils.rm_rf(File.join(dir, ".git"))
      File.write(File.join(dir, "Gemfile.eval"), GEMFILE)
    end

    def itself
      report = File.join(sandbox.root, "self.json")
      arguments = ["run", *SELF, "--jobs", "4", "--no-progress", "--report", report]
      exit, printed, usage = checkout.cli(*arguments, chdir: checkout.to_s, timeout: 3600)
      usage.timed(1).merge(exit.exited).merge("tail" => tail(printed))
    end

    def tail(printed) = printed.output.lines.grep(/mutants=/).last.to_s.strip
  end
end
