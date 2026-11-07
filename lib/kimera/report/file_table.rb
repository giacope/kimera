# frozen_string_literal: true

module Kimera
  module Report
  end
end

class Kimera::Report::FileTable
  MAX_ROWS = 15
  COLUMNS = { "survived" => 8, "uncovered" => 9, "killed" => 6, "score" => 6 }.freeze

  class Line
    def to_s = "  #{cells.zip(COLUMNS.values).map { |cell, width| cell.to_s.rjust(width) }.join("  ")}  #{label}"
  end

  class Heading < Line
    private

    def cells = COLUMNS.keys

    def label = "file"
  end

  class Row < Line
    def initialize(file, score)
      super()
      @file = file
      @score = score
    end

    def rank = [-count(:survived), -count(:no_coverage), @file]

    private

    def cells = [count(:survived), count(:no_coverage), count(:killed), @score.percent]

    def count(status) = @score.to_h.fetch(status)

    def label = @file
  end

  def initialize(io:)
    @io = io
  end

  def show(report)
    rows = report.score.by_file.map { |file, part| Row.new(file, part) }
    table(rows.sort_by(&:rank)) if rows.size > 1
  end

  private

  def table(rows)
    count = rows.size
    @io.puts("", "Files (#{count}, most survivors first):", Heading.new)
    rows.first(MAX_ROWS).each { |row| @io.puts(row) }
    @io.puts("  (+#{count - MAX_ROWS} more files)") if count > MAX_ROWS
  end
end
