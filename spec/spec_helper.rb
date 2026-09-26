# frozen_string_literal: true

# `COVERAGE=1 bin/spec`. Must start before kimera is required.
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    add_filter %r{/spec/}
    add_filter %r{/examples/}
    track_files "lib/**/*.rb"
  end
end

require "kimera"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :defined
  # Booting a suite sets KIMERA for the rest of the process; keep it per example.
  config.around do |example|
    before = ENV.fetch("KIMERA", nil)
    example.run
  ensure
    ENV["KIMERA"] = before
  end
end
