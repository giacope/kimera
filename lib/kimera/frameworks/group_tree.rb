# frozen_string_literal: true

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::GroupTree
  def initialize(top)
    @top = top
  end

  def examples = groups(@top).flat_map { |group| RSpec.configuration.filter_manager.prune(group.examples) }

  private

  def groups(group) = [group, *group.children.flat_map { |child| groups(child) }]
end
