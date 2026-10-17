# frozen_string_literal: true

# Runs the block with KIMERA_SEED set as kimera sets it for a seeded run, or
# unset, and puts back what was there.
module Seeded
  def seeded(seed)
    saved = ENV.fetch("KIMERA_SEED", nil)
    seed ? ENV.store("KIMERA_SEED", seed.to_s) : ENV.delete("KIMERA_SEED")
    yield
  ensure
    saved ? ENV.store("KIMERA_SEED", saved) : ENV.delete("KIMERA_SEED")
  end
end

RSpec.configure { |config| config.include(Seeded) }
