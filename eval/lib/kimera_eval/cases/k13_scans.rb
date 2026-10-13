# frozen_string_literal: true

module KimeraEval
  # K13: the cost and side effects of walking every module at overlay time,
  # on examples/rails_app booted and eager-loaded: how long the alias scan
  # takes, and how many deprecation warnings it triggers by calling methods
  # on Rails' deprecated-constant proxies.
  class ScansCase < Case
    ID = "K13"
    TITLE = "Overlay-time ObjectSpace scans: cost and side effects on a Rails app"
    BENCH = <<~RUBY
      ENV["RAILS_ENV"] = "test"
      require File.join(Dir.pwd, "config/environment")
      Rails.application.eager_load!
      require "kimera"
      require "kimera/execution/aliases"
      files = Dir[File.join(Dir.pwd, "app/**/*.rb")]
      modules = 0
      ObjectSpace.each_object(Module) { modules += 1 }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      Kimera::Execution::Aliases.new(files).follow { [] }
      puts "modules=\#{modules} seconds=\#{Process.clock_gettime(Process::CLOCK_MONOTONIC) - started}"
    RUBY

    def call
      app = sandbox.copy(File.join(ROOT, "examples", "rails_app"), "rails_app")
      FileUtils.rm_rf(%w[storage tmp log Gemfile.lock].map { |entry| File.join(app, entry) })
      env = { "BUNDLE_GEMFILE" => File.join(app, "Gemfile"), "KIMERA_PATH" => checkout.path }
      Shell.new(env: env, chdir: app, timeout: 900).run("bundle", "install")
      bench = Shell.new(env: env, chdir: app).run("bundle", "exec", "ruby", "-e", BENCH)
      seconds = bench.out[/seconds=([\d.]+)/, 1].to_f
      warnings = bench.err.scan(/DEPRECATION WARNING.*Aliases/).size
      { "pass" => warnings.zero? && seconds < 1.0, "summary" => { "scan_s" => seconds.round(3), "deprecation_warnings" => warnings } }
        .merge("modules" => bench.out[/modules=(\d+)/, 1].to_i, "exit" => bench.code)
    end
  end
end
