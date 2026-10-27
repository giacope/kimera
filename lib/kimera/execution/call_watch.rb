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
  def initialize(source, offset, id)
    @source = source
    @offset = offset
    @id = id
  end

  def source = written.first

  def watching? = written.last

  def reached?(touched) = !watching? || Array(touched).include?(@id)

  private

  def written = @_written ||= probed || [@source, false]

  def probed
    node = holder
    return unless node
    text = Kimera::SourceMap.new(@source).splice(Kimera::GuardProbe.new(node, [@id]).watch)
    [text, true] if Kimera::Syntax.parse(text).success?
  end

  def holder
    found = []
    Kimera::Rewrite::AstWalk.new(Kimera::Syntax.parse(@source).value).visit { |node| found << node if holds?(node) }
    found.max_by { |node| node.location.start_offset }
  end

  def holds?(node) = node.type == :def_node && span(node.location).cover?(@offset)

  def span(place) = place.start_offset...place.end_offset
end
