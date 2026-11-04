# frozen_string_literal: true

require "kimera/frameworks/suite"
require "kimera/results/run_report"

# The fields of kimera's results, which each result keeps to itself, for a
# spec that reads them: `using ResultFields` at the top of its file.
module ResultFields
  refine Kimera::MutantResult do
    (Kimera::MutantResult.members - [:duration]).each { |field| define_method(field) { super() } }

    def duration = super || 0.0
  end

  refine Kimera::LeakReport do
    Kimera::LeakReport.members.each { |field| define_method(field) { super() } }
  end

  refine Kimera::Frameworks::RunOutcome do
    Kimera::Frameworks::RunOutcome.members.each { |field| define_method(field) { super() } }
  end
end

using ResultFields

# have_attributes for a result: it reads the fields ResultFields opens.
RSpec::Matchers.define(:have_fields) do |expected|
  match { |actual| expected.all? { |field, value| values_match?(value, actual.send(field)) } }
  failure_message { |actual| "expected #{actual.inspect} to have fields #{expected.inspect}" }
end
