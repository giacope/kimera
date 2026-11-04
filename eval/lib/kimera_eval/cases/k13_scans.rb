# frozen_string_literal: true

module KimeraEval
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
    DISPOSABLE = %w[storage tmp log Gemfile.lock].freeze

    def call
      exit, printed = measure(sandbox.copy(File.join(ROOT, "examples", "rails_app"), "rails_app"))
      seconds = printed.to_s[/seconds=([\d.]+)/, 1].to_f
      warnings = printed.output.scan(/DEPRECATION WARNING.*Aliases/).size
      summary = { "scan_s" => seconds.round(3), "deprecation_warnings" => warnings }
      { "pass" => warnings.zero? && seconds < 1.0, "summary" => summary }.merge(scanned(exit, printed))
    end

    def scanned(exit, printed) = { "modules" => printed.to_s[/modules=(\d+)/, 1].to_i }.merge(exit.exited)

    private

    def measure(app)
      FileUtils.rm_rf(DISPOSABLE.map { |entry| File.join(app, entry) })
      bench(app)
    end

    def bench(app)
      env = { "BUNDLE_GEMFILE" => File.join(app, "Gemfile"), "KIMERA_PATH" => checkout.to_s }
      shell = Shell.new(env: env, chdir: app)
      shell.run("bundle", "install")
      shell.run("bundle", "exec", "ruby", "-e", BENCH)
    end
  end
end
