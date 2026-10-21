# frozen_string_literal: true

module Kimera
  module Execution
  end
end

module Kimera::Execution::Fault
  refine(Exception) do
    def headline = "#{self.class}: #{message}"

    def last_words = Kimera::Execution::LastWords.new(self).to_s

    def echo(_duty) = self
  end
end
