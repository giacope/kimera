# frozen_string_literal: true

module Kimera
  module Execution
    class NullProgress
      def start(_total, _label = nil); end

      def tick(_status = nil); end

      def finish; end

      def note(_text); end

      NONE = new.freeze
    end
  end
end
