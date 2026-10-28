# frozen_string_literal: true

class Kimera::Execution::Shift
  class Unmapped
    def initialize(adapter)
      @adapter = adapter
    end

    def fetch(_id, &) = @adapter.test_ids
  end
end
