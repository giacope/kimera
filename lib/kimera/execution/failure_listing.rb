# frozen_string_literal: true

module Kimera
  module Execution
  end
end

# The first line of each failure, and, for a failure given as [message,
# detail], the first lines of its detail: what a lost test's worker left.
Kimera::Execution::FailureListing =
  Data.define(:failures) do
    limit = 5
    depth = 4
    define_method(:lines) do
      shown = failures.first(limit).flat_map { |test_id, failure| entry(test_id, *failure) }
      hidden = failures.size - limit
      hidden.positive? ? [*shown, "  … and #{hidden} more"] : shown
    end
    define_method(:entry) do |test_id, message = nil, detail = nil|
      first = message.to_s.lines.first.to_s.strip
      ["  #{test_id}#{": #{first}" unless first.empty?}", *detail.to_s.lines.first(depth).map { "    #{it.rstrip}" }]
    end
    private(:entry)
  end
