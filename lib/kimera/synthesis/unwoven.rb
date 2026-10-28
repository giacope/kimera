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
      unguarded = Kimera::Unguarded.new(woven).node
      Kimera::Outline.new(unguarded).shape == Kimera::Outline.new(holder).shape
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
      begin
        normal = Kimera::Rewrite::NumberedParams.new(@tree).normalize
        Kimera::Rewrite::AstWalk.new(normal).nodes
      end
  end
end
