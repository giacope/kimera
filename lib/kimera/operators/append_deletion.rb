# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::AppendDeletion < Kimera::Operators::Base
  def key = "append_deletion"

  def statement? = true

  def variants(node, **)
    deletion(node) if node.is_a?(CallNode) && node.name == :<< && node.receiver
  end
end
