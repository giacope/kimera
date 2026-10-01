# frozen_string_literal: true

require_relative "../error"
require_relative "../listing"

module Kimera
  module Execution
  end
end

class Kimera::Execution::BaselineFailure < Kimera::Error; end

require_relative "baseline_failure/breakdown"
require_relative "baseline_failure/mirror"
require_relative "baseline_failure/summary"
