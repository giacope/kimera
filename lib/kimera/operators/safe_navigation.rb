# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::SafeNavigation < Kimera::Operators::Base
  class << self
    def key = "safe_navigation"
  end

  def variants(node, **)
    return unless node.is_a?(CallNode)
    return unless node.safe_navigation?
    solo("&. => .", "csend_to_send")
  end
end
