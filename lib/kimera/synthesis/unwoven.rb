# frozen_string_literal: true

require_relative "../rewrite/ast_walk"
require_relative "../rewrite/numbered_params"
require_relative "outline"
require_relative "unguarded"

class Kimera::Unwoven
  def initialize(tree)
    @tree = tree
  end

  def keeps?(holders) = holders.all? { |holder| kept?(holder) }

  private

  def kept?(holder)
    woven(holder).any? do |woven|
      Kimera::Outline.new(Kimera::Unguarded.new(woven).node).shape == Kimera::Outline.new(holder).shape
    end
  end

  def woven(holder)
    line = holder.location.start_line
    named = name(holder)
    nodes.lazy.select { |node| node.type == holder.type && node.location.start_line == line && name(node) == named }
      .first(1)
  end

  def name(node) = node.deconstruct_keys(nil).slice(:name)

  def nodes
    @_nodes ||=
      [].tap do |found|
        Kimera::Rewrite::AstWalk.new(Kimera::Rewrite::NumberedParams.new(@tree).normalize).visit { |node| found << node }
      end
  end
end
