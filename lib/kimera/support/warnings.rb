# frozen_string_literal: true

module Kimera
  module Warnings
    module_function

    def silence
      previous = $VERBOSE
      $VERBOSE = nil
      yield
    ensure
      $VERBOSE = previous
    end
  end
end
