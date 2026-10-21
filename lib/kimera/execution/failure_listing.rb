# frozen_string_literal: true

module Kimera
  module Execution
  end
end

Kimera::Execution::FailureListing =
  Data.define(:failures) do
    limit = 5
    define_method(:lines) do
      shown =
        failures.first(limit).map do |test_id, failure|
          first = failure.to_s.lines.first.to_s.strip
          "  #{test_id}#{": #{first}" unless first.empty?}"
        end
      hidden = failures.size - limit
      hidden.positive? ? [*shown, "  … and #{hidden} more"] : shown
    end
  end
