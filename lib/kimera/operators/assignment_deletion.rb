# frozen_string_literal: true

require_relative "base"
require_relative "enclosed"
require_relative "reassignments"

class Kimera::Operators::AssignmentDeletion < Kimera::Operators::Base
  BLANK = ->(node) { node.is_a?(InstanceVariableWriteNode) && node.value.is_a?(NilNode) }

  def key = "assignment_deletion"

  def statement? = true

  def survey(root)
    @_rebinds = Kimera::Operators::Reassignments.new(root)
    @_blanks = Kimera::Operators::Enclosed.new(root, %i[initialize], &BLANK)
    self
  end

  def variants(node, **)
    return unless node.is_a?(InstanceVariableWriteNode) || rebinds.include?(node)
    solo("drop assignment to `#{node.name}`", "assigned_value") unless blanks.include?(node)
  end

  private

  def rebinds = @_rebinds || Kimera::Operators::Survey::NONE

  def blanks = @_blanks || Kimera::Operators::Survey::NONE
end
