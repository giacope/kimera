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
  # When kimera runs on itself, the run's mutant is on while these examples
  # run; an example that drives the switch hands it back to the next one.
  config.around { |example| Kimera::RUNTIME.during(Kimera::RUNTIME.active) { example.run } }
  # Woven code an example evaluates registers its visibility flips with the
  # process-wide runtime, under ids 1, 2, ... that later examples use too:
  # they leave with the example. Kept, each later switch to such an id walked
  # the object space for aliases of a class nothing holds (0.5 s by
  # spec/property), and the Shift children of worker_pool_spec missed its
  # watchdog.
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
