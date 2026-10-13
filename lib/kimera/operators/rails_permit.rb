# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::RailsPermit < Kimera::Operators::Base
  def key = "rails_permit"

  def variants(node, **)
    return unless call(node).chained?(:permit)
    words = arguments(node)
    return unless words.all? { |a| plain?(a) }
    indexed(words)
  end

  private

  def indexed(words)
    words.each_index.map { |index| variant(words, index) }
  end

  def variant(words, index)
    Kimera::Operators::Variant.new(
      label: "permit: drop #{words[index].location.slice}",
      directive: directive("drop_argument", index: index)
    )
  end

  def plain?(node)
    !node.is_a?(SplatNode) && !node.is_a?(KeywordHashNode) &&
      !node.is_a?(BlockArgumentNode)
  end
end
