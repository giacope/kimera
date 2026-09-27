# frozen_string_literal: true

module Kimera::IgnoreList::Drift
  private

  def hits = exact.empty? ? drifted : exact

  def exact = @_exact ||= matching(anchors)

  def drifted = @_drifted ||= anchors[:line] && anchors[:label] ? single(matching(anchors.except(:line))) : []

  def single(found) = found.one? ? found : []
end
