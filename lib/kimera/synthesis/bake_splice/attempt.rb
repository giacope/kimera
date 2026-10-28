# frozen_string_literal: true

class Kimera::BakeSplice::Attempt
  def initialize(from, to, text, grouping)
    @from = from
    @to = to
    @text = text
    @grouping = grouping
  end

  def self.plain(from, to, text) = new(from, to, text, nil)

  def self.grouped(from, to, text) = new(from, to, text, from + text.bytesize)

  def grouped?(node)
    location = node.location
    node.type == :parentheses_node && [location.start_offset, location.end_offset] == [@from, @grouping]
  end

  def edit = [@from, @to, @text]
end
