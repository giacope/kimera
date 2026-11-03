# frozen_string_literal: true

# Where a bay runs its child and with which slot: what it hands the plan it
# builds the child's command with.
module BaySeat
  def seat(bay)
    plan = Object.new
    plan.define_singleton_method(:command) { |mirror, _locations, _ledger, slot:, **| [mirror, slot] }
    bay.command(plan, [], nil, first: false)
  end
end

RSpec.configure { |config| config.include(BaySeat) }
