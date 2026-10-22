# frozen_string_literal: true

module Kimera
  class Scribe
    class Name
      LABEL = /\A[A-Za-z_][A-Za-z0-9_]*[?!]?\z/

      def initialize(name)
        @name = name
      end

      def symbol
        text = @name.to_s
        text.ascii_only? ? @name.inspect : %(:"#{Quote.new(text).text}")
      end

      def label
        text = @name.to_s
        text.match?(LABEL) ? "#{text}:" : %("#{Quote.new(text).text}":)
      end
    end
  end
end
