# frozen_string_literal: true

module Kimera
  module Execution
    module NullProgress
      module_function

      def start(_total, _label = nil); end

      def tick(_status = nil); end

      def finish; end

      def enabled? = false
    end
  end
end
