# frozen_string_literal: true

require_relative "../rewrite/ast_walk"
require_relative "part_splice"
require_relative "splice_reopening"

class Kimera::PointLines
  def initialize(map, location)
    @map = map
    @location = location
  end

  def kept?(text)
    lines = text.lines
    base.size == lines.size && base.each_index.all? { |index| owned.include?(index + 1) || base[index] == lines[index] }
  end

  private

  def base = @_base ||= @map.splice(Kimera::SpliceReopening.new(@map).edits).lines

  def owned
    @_owned ||=
      @location.range.to_set.tap do |found|
        Kimera::Rewrite::AstWalk.new(@map.ast).visit { |node| found.merge(body(node)) if held?(node) }
      end
  end

  def held?(node)
    return false unless node.respond_to?(:heredoc?) && node.heredoc?
    from = @location.start_offset
    node.location.start_offset.between?(from, @location.finish - 1) ||
      (Kimera::PartSplice.new(node).body.start_offset..node.closing_loc.start_offset).cover?(from)
  end

  def body(heredoc)
    verbatim = heredoc.opening_loc.slice.match?(Kimera::PartSplice::VERBATIM)
    (verbatim ? heredoc.location : Kimera::PartSplice.new(heredoc).body).start_line..heredoc.closing_loc.start_line
  end
end
