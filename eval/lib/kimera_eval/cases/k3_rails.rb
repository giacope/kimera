# frozen_string_literal: true

module KimeraEval
  # K3: examples/rails_app (Rails 8.1, sqlite) end to end, Minitest and
  # RSpec, against an oracle that bakes each mutant and runs `bin/rails test`
  # (or `rspec`) fresh. Modes: serial, 4 workers with per-worker databases,
  # --isolate-db with both, and --isolated.
  class RailsCase < Case
    ID = "K3"
    TITLE = "Real Rails app end to end (validations, callbacks, transactions, per-worker DBs)"
    MODES = [%w[--jobs 1], %w[--jobs 4], %w[--isolate-db], %w[--jobs 4 --isolate-db], %w[--isolated --jobs 4]].freeze
    SUITES = { "minitest" => [[], %w[bin/rails test]], "rspec" => [%w[--config .kimera-rspec.yml], %w[bundle exec rspec]] }.freeze

    def call
      app = prepare
      @oracles = {}
      runs = SUITES.to_h { |name, (args, command)| [name, suite(name, app, args, command)] }
      runs["minitest"]["--isolated, relative path gem"] = relative(app)
      flat = runs.values.flat_map(&:values)
      total = totals(flat)
      { "pass" => total.values_at("false_survived", "false_killed", "errors").sum.zero? && flat.sum { |run| run["leaks"].to_i }.zero?, "summary" => headline(total, flat) }
        .merge("totals" => total, "runs" => runs)
    end

    private

    def env = { "BUNDLE_GEMFILE" => File.join(@app, "Gemfile"), "KIMERA_PATH" => checkout.path, "PARALLEL_WORKERS" => "1" }

    def prepare
      @app = sandbox.copy(File.join(ROOT, "examples", "rails_app"), "rails_app")
      FileUtils.rm_rf(%w[storage tmp log Gemfile.lock].map { |entry| File.join(@app, entry) })
      install = Shell.new(env: env, chdir: @app, timeout: 900).run("bundle", "install")
      raise("rails_app bundle install failed:\n#{install.output[-2000..]}") unless install.ok?
      @app
    end

    def suite(name, app, args, command)
      truth = @oracles[name] = oracle(app, command: command, env: env)
      differential(app, MODES, args: args, oracle: truth, env: env.merge("BUNDLE_GEMFILE" => "Gemfile"))
    end

    # The Gemfile names kimera by a relative path (../..), as a monorepo
    # names its engines: the app sits at examples/rails_app under a tree
    # whose root links to the checkout.
    def relative(app)
      tree = File.join(sandbox.root, "relative")
      FileUtils.mkdir_p(File.join(tree, "examples"))
      %w[lib exe kimera.gemspec README.md CHANGELOG.md LICENSE.txt skills schema].each do |entry|
        FileUtils.ln_s(File.join(checkout.path, entry), File.join(tree, entry)) if File.exist?(File.join(checkout.path, entry))
      end
      placed = File.join(tree, "examples", "rails_app")
      FileUtils.cp_r(app, placed)
      local = { "BUNDLE_GEMFILE" => File.join(placed, "Gemfile"), "KIMERA_PATH" => nil, "PARALLEL_WORKERS" => "1" }
      FileUtils.rm_f(File.join(placed, "Gemfile.lock"))
      Shell.new(env: local, chdir: placed, timeout: 900).run("bundle", "install")
      Differential.new(checkout, placed, oracle: @oracles.fetch("minitest"), env: local).call(%w[--isolated --jobs 4])
    end

    def headline(total, flat)
      judged = total["mutants"] - total["abstained"] - total["unbakeable"]
      total.slice("false_survived", "false_killed", "abstained", "errors")
        .merge("agreement_pct" => judged.zero? ? nil : (100.0 * total["agree"] / judged).round(1))
        .merge("leaks" => flat.sum { |run| run["leaks"].to_i }, "rejudged" => flat.sum { |run| run["rejudged"].to_i })
        .merge("wall_s" => flat.sum { |run| run["wall_s"].to_f }.round(1))
    end
  end
end
