# frozen_string_literal: true

require_relative "base"

# Deletes a statement that appends with `<<` (`@log << name`, `traits <<
# trait`), which statement_deletion leaves alone: it deletes only calls with
# a method name, not operator calls.
class Kimera::Operators::AppendDeletion < Kimera::Operators::Base
  def key = "append_deletion"

  def statement? = true

  def variants(node, **)
    deletion(node) if node.is_a?(CallNode) && node.name == :<< && node.receiver
  end
end
