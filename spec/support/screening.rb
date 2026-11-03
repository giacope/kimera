# frozen_string_literal: true

# Whether a test filter screens a run at all: an inactive one hands back the
# coverage it is given and narrows nothing.
module Screening
  def screens?(filter)
    filter.screen({}) { return true }
    false
  end

  # What the filter keeps and settles of COVERAGE, and what it narrows the run to.
  def screened(filter, coverage)
    narrowed = []
    [*filter.screen(coverage) { |kept| narrowed << kept }, narrowed]
  end
end

RSpec.configure { |config| config.include(Screening) }
