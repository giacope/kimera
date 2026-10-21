# frozen_string_literal: true

class Kimera::CLI::Survivors::Context
  AROUND = 2

  def initialize(row, root:)
    @row = row
    @root = root
  end

  def lines
    source = text
    return [] unless source
    return ["  (#{@row["file"]} changed since the report; no source context)"] unless current?(source)
    window(source).map { |number| numbered(source, number) }
  end

  private

  def text
    path = File.join(@root, @row["file"].to_s)
    File.readlines(path, encoding: Encoding::UTF_8).map(&:scrub) if first && File.file?(path)
  end

  def first = @row["line"]

  def last = @row["end_line"] || first

  def current?(source)
    expected = @row["original"].to_s.lines.first.to_s.strip
    source.fetch(first - 1, "").include?(expected)
  end

  def window(source) = ([first - AROUND, 1].max..[last + AROUND, source.size].min)

  def numbered(source, number)
    marker = (first..last).cover?(number) ? ">" : " "
    "  #{marker} #{number.to_s.rjust((last + AROUND).to_s.size)} | #{source.fetch(number - 1)}".rstrip
  end
end
