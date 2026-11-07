# frozen_string_literal: true

module Screening
  def screens?(filter)
    filter.screen({}) { return true }
    false
  end

  def screened(filter, coverage)
    narrowed = []
    [*filter.screen(coverage) { |kept| narrowed << kept }, narrowed]
  end
end

RSpec.configure { |config| config.include(Screening) }
