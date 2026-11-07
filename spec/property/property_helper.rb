# frozen_string_literal: true

require "spec_helper"
require "pbt"

Dir[File.join(__dir__, "support", "*.rb")].each { |f| require f }

module PropertyRuns
  SEED = Integer(ENV.fetch("PBT_SEED") { Random.new_seed % (2**32) })
  SCALE = Float(ENV.fetch("PBT_SCALE", "1"))

  def for_all(*arbitraries, runs: 100, **named, &)
    Pbt.assert(num_runs: (runs * SCALE).ceil, seed: SEED) { Pbt.property(*arbitraries, **named, &) }
  end

  def sample(items, count) = items.sort.sample(count, random: Random.new(SEED))
end

RSpec.configure { |config| config.include(PropertyRuns, file_path: %r{/spec/property/}) }
