# frozen_string_literal: true

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
  config.around do |example|
    before = ENV.fetch("KIMERA", nil)
    example.run
  ensure
    ENV["KIMERA"] = before
  end
  config.around { |example| Kimera::RUNTIME.during(Kimera::RUNTIME.active) { example.run } }
  config.around do |example|
    flips = Kimera::RUNTIME.__send__(:hidden).flips
    kept = flips.dup
    example.run
  ensure
    flips.replace(kept)
  end
  config.around do |example|
    world = RSpec.world
    quitting = world.wants_to_quit
    failed = world.non_example_failure
    example.run
  ensure
    world.wants_to_quit = quitting
    world.non_example_failure = failed
  end
end
