# frozen_string_literal: true

require "prism"

module Kimera
end

class Kimera::Branches
  def initialize(node)
    @node = node
  end

  def bodies = [@node.statements, *rest(following)]

  def following
    return @node.else_clause if @node.is_a?(Prism::UnlessNode)
    @node.respond_to?(:subsequent) ? @node.subsequent : @node.consequent
  end

  private

  def rest(tail)
    case tail
    when Prism::IfNode then Kimera::Branches.new(tail).bodies
    when Prism::ElseNode then [tail.statements]
    else []
    end
  end
end
