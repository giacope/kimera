# frozen_string_literal: true

class Kimera::GuardSpan
  def initialize(node)
    @node = node
  end

  def self.of(node)
    bare = node.type == :begin_node && !node.begin_keyword_loc
    bare ? Kimera::GuardSpan::Body.new(node) : new(node)
  end

  def from = node.location.start_offset

  def to = node.location.end_offset

  def slice = node.slice

  def text(written) = written

  private

  attr_reader :node
end

require_relative "guard_span/body"
