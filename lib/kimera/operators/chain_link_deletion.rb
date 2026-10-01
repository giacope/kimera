# frozen_string_literal: true

require "prism"
require_relative "base"

class Kimera::Operators::ChainLinkDeletion < Kimera::Operators::Base
  def key = "chain_link_deletion"

  def variants(node, **)
    return unless deletable?(node)
    solo("drop chain link `.#{node.receiver.name}`", "drop_receiver_link")
  end

  private

  def deletable?(node)
    return false unless node.is_a?(CallNode)
    link = node.receiver
    return false unless link.is_a?(CallNode) && link.receiver
    return false if link.block.is_a?(BlockNode)
    identifier?(link)
  end
end
