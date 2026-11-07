# frozen_string_literal: true

require_relative "../rewrite/ast_walk"
require_relative "part_splice"
require_relative "splice_reopening"

class Kimera::PointLines
  WORDS = "%"

  def initialize(map, point)
    @map = map
    @point = point
  end

  def kept?(text)
    lines = text.lines
    base.size == lines.size && base.each_index.all? { |index| owned?(index + 1) || base[index] == lines[index] }
  end

  private

  def base = @_base ||= @map.splice(Kimera::SpliceReopening.new(@map).edits).lines

  def owned?(line) = @point.fits?(line: line) || owned.include?(line)

  def owned
    @_owned ||=
      Set.new.tap do |found|
        Kimera::Rewrite::AstWalk.new(@map.ast).visit do |node|
          found.merge(body(node)) if held?(node)
          found.merge(node.location.start_line..node.location.end_line) if worded?(node)
        end
      end
  end

  def worded?(node)
    node.type == :array_node && node.opening_loc&.slice&.start_with?(WORDS) &&
      @point.fits?(inside: [node.location.start_offset, node.location.end_offset])
  end

  def held?(node)
    return false unless node.respond_to?(:heredoc?) && node.heredoc?
    @point.fits?(covers: node.location.start_offset) ||
      @point.fits?(entered: [Kimera::PartSplice.new(node).body.start_offset, node.closing_loc.start_offset])
  end

  def body(heredoc)
    part = Kimera::PartSplice.new(heredoc)
    (part.verbatim? ? heredoc.location : part.body).start_line..heredoc.closing_loc.start_line
  end
end
