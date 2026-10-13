# frozen_string_literal: true

module KimeraEval
  # K3: examples/rails_app (Rails 8.1, sqlite) end to end, Minitest and
  # RSpec, against an oracle that bakes each mutant and runs `bin/rails test`
  # (or `rspec`) fresh. Modes: serial, 4 workers with per-worker databases,
  # --isolate-db with both, and --isolated, also with the app placed so its
  # Gemfile's relative path to kimera resolves (as a monorepo's engines do).
  class RailsCase < Case
    ID = "K3"
    TITLE = "Real Rails app end to end (validations, callbacks, transactions, per-worker DBs)"
    MODES = [%w[--jobs 1], %w[--jobs 4], %w[--isolate-db], %w[--jobs 4 --isolate-db], %w[--isolated --jobs 4]].freeze
    SUITES = { "minitest" => [[], %w[bin/rails test]], "rspec" => [%w[--config .kimera-rspec.yml], RSPEC] }.freeze
    DISPOSABLE = %w[storage tmp log Gemfile.lock].freeze
    LINKED = %w[lib exe kimera.gemspec README.md CHANGELOG.md LICENSE.txt skills schema].freeze

    def call
      app = prepare(sandbox.copy(File.join(ROOT, "examples", "rails_app"), "rails_app"), environment)
      runs = SUITES.to_h { |name, (arguments, command)| [name, suite(app, arguments, command)] }
      runs["minitest"]["--isolated, relative path gem"] = relative(app)
      measured(runs)
    end

    private

    def environment(app = nil)
      { "BUNDLE_GEMFILE" => app && File.join(app, "Gemfile"), "KIMERA_PATH" => checkout.path }
        .merge("PARALLEL_WORKERS" => "1")
    end

    def prepare(app, env)
      FileUtils.rm_rf(DISPOSABLE.map { |entry| File.join(app, entry) })
      install(app, env).then { |result| result.ok? ? app : raise(SetupError, "bundle install failed in #{app}") }
    end

    def install(app, env)
      Shell.new(env: env.merge("BUNDLE_GEMFILE" => File.join(app, "Gemfile")), chdir: app, timeout: 900)
        .run("bundle", "install")
    end

    def suite(app, arguments, command)
      env = environment(app)
      @truth ||= {}
      truth = @truth[command] = oracle(app, Oracle::Runner.new(command, env))
      differential(target(app, arguments: arguments, env: env.merge("BUNDLE_GEMFILE" => "Gemfile")), MODES, truth)
    end

    def relative(app)
      placed = place(app)
      local = environment(placed).merge("KIMERA_PATH" => nil)
      prepare(placed, local)
      Differential.new(checkout, target(placed, env: local), oracle: @truth.fetch(SUITES["minitest"].last))
        .call(%w[--isolated --jobs 4])
    end

    def place(app)
      placed = File.join(sandbox.root, "relative", "examples", "rails_app")
      LINKED.each { |entry| link(entry, File.dirname(placed, 2)) }
      FileUtils.cp_r(app, placed)
      placed
    end

    def link(entry, tree)
      source = File.join(checkout.path, entry)
      FileUtils.mkdir_p(File.join(tree, "examples"))
      FileUtils.ln_s(source, File.join(tree, entry)) if File.exist?(source)
    end

    def measured(runs)
      flat = runs.values.flat_map(&:values)
      total = totals(flat)
      leaks = flat.sum { |run| run["leaks"].to_i }
      { "pass" => total.values_at("false_survived", "false_killed", "errors").sum.zero? && leaks.zero? }
        .merge("summary" => summary(total, flat, leaks), "totals" => total, "runs" => runs)
    end

    def summary(total, flat, leaks)
      rejudged = flat.sum { it["rejudged"].to_i }
      headline(total).merge("errors" => total["errors"], "leaks" => leaks, "rejudged" => rejudged)
        .merge("wall_s" => flat.sum { |run| run["wall_s"].to_f }.round(1))
    end
  end
end
