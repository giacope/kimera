# frozen_string_literal: true

module Kimera
  module Report
  end
end

class Kimera::Report::FileTable
  MAX_ROWS = 15
  COLUMNS = { "survived" => 8, "uncovered" => 9, "killed" => 6, "score" => 6 }.freeze

  Row =
    Data.define(:file, :report) do
      def cells = [report.survived.size, report.uncovered.size, report.killed.size, report.percent]

      def rank = [-report.survived.size, -report.uncovered.size, file]
    end

  def initialize(io:)
    @io = io
  end

  def show(report)
    rows = report.by_file.map { |file, part| Row.new(file, part) }
    table(rows.sort_by(&:rank)) if rows.size > 1
  end

  private

  def table(rows)
    count = rows.size
    @io.puts("", "Files (#{count}, most survivors first):", line(COLUMNS.keys, "file"))
    rows.first(MAX_ROWS).each { |row| @io.puts(line(row.cells, row.file)) }
    @io.puts("  (+#{count - MAX_ROWS} more files)") if count > MAX_ROWS
  end

  def line(cells, file)
    "  #{cells.zip(COLUMNS.values).map { |cell, width| cell.to_s.rjust(width) }.join("  ")}  #{file}"
  end
end
