# frozen_string_literal: true

module Kimera
  class Unmutated
    def initialize(file:, start_line:, end_line:, reason:)
      @file = file
      @start_line = start_line
      @end_line = end_line
      @reason = reason
    end

    def to_h = { "file" => @file, "start_line" => @start_line, "end_line" => @end_line, "reason" => @reason }

    def place = @start_line == @end_line ? "#{@file}:#{@start_line}" : "#{@file}:#{@start_line}-#{@end_line}"

    def line = "#{place}  #{@reason}"

    def touched?(changed) = Array(changed[@file]).any? { |line| (@start_line..@end_line).cover?(line) }
  end

  class << Unmutated
    BLOCK = "code in a block outside any method runs at load or as a DSL callback " \
      "kimera can't swap, so it is not mutated"
    WHOLE = {
      unparsed: "does not parse, so nothing in it is mutated: ",
      unread: "could not be read, so nothing in it is mutated: ",
      unscanned: "kimera could not scan it, so nothing in it is mutated (a kimera bug, please report it): "
    }.freeze

    def from_h(hash) = new(**hash.transform_keys(&:to_sym))

    def block(file, first, last) = new(file: file, start_line: first, end_line: last, reason: BLOCK)

    def whole(file, last, kind, detail)
      new(file: file, start_line: 1, end_line: last, reason: "#{WHOLE.fetch(kind)}#{detail}")
    end
  end
end
