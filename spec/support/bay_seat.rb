# frozen_string_literal: true

module BaySeat
  def seat(bay)
    plan = Object.new
    plan.define_singleton_method(:command) { |mirror, _locations, _ledger, slot:, **| [mirror, slot] }
    bay.command(plan, [], nil, first: false)
  end
end

RSpec.configure { |config| config.include(BaySeat) }
