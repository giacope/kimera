# frozen_string_literal: true

require_relative "../parsing/syntax"
require_relative "../rewrite/ast_walk"
require_relative "../synthesis/guard_probe"
require_relative "../synthesis/source_map"

module Kimera
  module Execution
  end
end

class Kimera::Execution::CallWatch
  def initialize(source, point, id, probes = Kimera::GuardProbe)
    @source = source
    @point = point
    @id = id
    @probes = probes
  end

  def source = written.fetch(0)

  def watching? = written.fetch(1)

  def reached?(touched) = !watching? || Array(touched).include?(@id)

  private

  def written = @_written ||= probed.fetch(0) { [@source, false] }

  def probed
    holder.filter_map do |node|
      text = Kimera::SourceMap.new(@source).splice(@probes.new(node, [@id]).watch)
      [text, true] if Kimera::Syntax.parse(text).success?
    end
  end

  def holder
    found = []
    Kimera::Rewrite::AstWalk.new(tree).visit { |node| found << node if holds?(node) }
    found.max_by(1) { |node| node.location.start_offset }
  end

  def tree = Kimera::Syntax.parse(@source).value

  def holds?(node) = node.type == :def_node && @point.fits?(entered: span(node.location))

  def span(place) = [place.start_offset, place.end_offset - 1]
end
