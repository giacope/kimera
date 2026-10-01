# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::RailsPermit < Kimera::Operators::Base
  def key = "rails_permit"

  def variants(node, **)
    return unless call(node).chained?(:permit)
    args = arguments(node)
    return unless args.all? { |a| plain?(a) }
    indexed(args)
  end

  private

  def indexed(args)
    args.each_index.map { |index| variant(args, index) }
  end

  def variant(args, index)
    Kimera::Operators::Variant.new(
      label: "permit: drop #{args[index].location.slice}",
      directive: directive("drop_argument", index: index)
    )
  end

  def plain?(node)
    !node.is_a?(SplatNode) && !node.is_a?(KeywordHashNode) &&
      !node.is_a?(BlockArgumentNode)
  end
end
