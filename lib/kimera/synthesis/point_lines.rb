# frozen_string_literal: true

require_relative "../rewrite/ast_walk"
require_relative "part_splice"
require_relative "splice_reopening"

class Kimera::PointLines
  WORDS = "%"

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
        Kimera::Rewrite::AstWalk.new(@map.ast).visit do |node|
          found.merge(body(node)) if held?(node)
          found.merge(node.location.start_line..node.location.end_line) if worded?(node)
        end
      end
  end

  def worded?(node)
    node.type == :array_node && node.opening_loc&.slice&.start_with?(WORDS) &&
      @location.inside?(node.location.start_offset, node.location.end_offset)
  end

  def held?(node)
    return false unless node.respond_to?(:heredoc?) && node.heredoc?
    @location.covers?(node.location.start_offset) ||
      @location.starts_between?(Kimera::PartSplice.new(node).body.start_offset, node.closing_loc.start_offset)
  end

  def body(heredoc)
    part = Kimera::PartSplice.new(heredoc)
    (part.verbatim? ? heredoc.location : part.body).start_line..heredoc.closing_loc.start_line
  end
end
