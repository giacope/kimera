# frozen_string_literal: true

module KimeraEval
  # S1: wall time on real suites, and (dry-inflector) verdicts against the
  # oracle: examples/sample_app at --jobs 1 and 4, dry-inflector's lib with
  # --operators all at --jobs 4, and kimera's own operators/ and rewrite/
  # mutated by itself at --jobs 4 (its own .kimera.yml).
  class SpeedCase < Case
    ID = "S1"
    TITLE = "Speed on real suites (sample_app, dry-inflector, kimera self-host subset)"
    INFLECTOR = "https://github.com/dry-rb/dry-inflector.git"
    REVISION = "b6a2819f0cf1bc0c24e024bbdf73f4f67003cbc9"
    GEMFILE = <<~RUBY
      source "https://rubygems.org"
      gemspec path: "."
      gem "rspec", "~> 3.13"
      gem "warning"
      gem "kimera", path: ENV.fetch("KIMERA_PATH")
    RUBY
    SELF = %w[lib/kimera/operators lib/kimera/rewrite].freeze

    def call
      runs = sample.merge(context.quick? ? {} : { "dry-inflector --jobs 4" => inflector, "self-host subset --jobs 4" => self_host })
      { "pass" => runs.values.none? { |run| run["error"] }, "summary" => runs.transform_values { |run| run["wall_s"] } }
        .merge("runs" => runs)
    end

    private

    def sample
      dir = File.join(ROOT, "examples", "sample_app")
      [%w[--jobs 1], %w[--jobs 4]].to_h do |mode|
        copy = sandbox.copy(dir)
        result = checkout.kimera("run", "app", "--tests", "spec/**/*_spec.rb", *mode, "--no-progress", chdir: copy)
        ["sample_app #{mode.join(" ")}", { "wall_s" => result.wall.round(2), "exit" => result.code }]
      end
    end

    def inflector
      dir = clone
      env = { "BUNDLE_GEMFILE" => File.join(dir, "Gemfile.eval"), "KIMERA_PATH" => checkout.path }
      Shell.new(env: env, chdir: dir, timeout: 900).run("bundle", "install")
      truth = oracle(dir, command: %w[bundle exec rspec], env: env)
      run = differential(dir, [%w[--jobs 4]], args: %w[lib --tests spec/**/*_spec.rb --operators all], oracle: truth, env: env)
      run.values.first.except("disagreements").merge("disagreements" => run.values.first["disagreements"]&.first(20))
    end

    def clone
      cache = File.join(ROOT, "eval", "tmp", "dry-inflector")
      Shell.new.run("git", "clone", "-q", INFLECTOR, cache) unless File.directory?(cache)
      Shell.new(chdir: cache).run("git", "checkout", "-q", REVISION)
      dir = sandbox.copy(cache, "dry-inflector")
      FileUtils.rm_rf(File.join(dir, ".git"))
      File.write(File.join(dir, "Gemfile.eval"), GEMFILE)
      dir
    end

    def self_host
      result = checkout.kimera("run", *SELF, "--jobs", "4", "--no-progress", "--report", File.join(sandbox.root, "self.json"),
                               chdir: checkout.path, timeout: 3600)
      { "wall_s" => result.wall.round(1), "exit" => result.code, "tail" => result.output.lines.grep(/mutants=/).last.to_s.strip }
    end
  end
end
