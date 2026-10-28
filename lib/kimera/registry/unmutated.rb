# frozen_string_literal: true

module Kimera
  Unmutated =
    Data.define(:file, :start_line, :end_line, :reason) do
      def to_h = super.transform_keys(&:to_s)

      def place = start_line == end_line ? "#{file}:#{start_line}" : "#{file}:#{start_line}-#{end_line}"

      def line = "#{place}  #{reason}"

      def touches?(lines) = lines.any? { |line| (start_line..end_line).cover?(line) }
    end

  class << Unmutated
    def from_h(hash) = new(**hash.transform_keys(&:to_sym))
  end

  Unmutated::BLOCK = "code in a block outside any method runs at load or as a DSL callback " \
    "kimera can't swap, so it is not mutated"
  Unmutated::UNPARSED = "does not parse, so nothing in it is mutated: "
  Unmutated::UNREAD = "could not be read, so nothing in it is mutated: "
  Unmutated::UNSCANNED = "kimera could not scan it, so nothing in it is mutated (a kimera bug, please report it): "
end
