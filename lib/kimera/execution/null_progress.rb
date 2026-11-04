# frozen_string_literal: true

module Kimera
  module Execution
    class NullProgress
      UNSEEN = ->(_status = nil) {}

      def during(_total, _label = nil) = yield(UNSEEN)

      def note(_text); end
    end
  end
end
