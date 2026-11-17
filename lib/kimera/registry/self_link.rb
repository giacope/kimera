# frozen_string_literal: true

require_relative "memoization"
require_relative "../parsing/syntax"
require_relative "../parsing/syntax_types"

class Kimera::SelfLink
  include Kimera::SyntaxTypes

  PRIVILEGE = "leaves a bare `self` receiver, whose private calls a warm guard would refuse (evaluate with reload)"

  def initialize(source)
    @source = source
  end

  def ranges
    result = Kimera::Syntax.parse(@source)
    result.failure? ? [] : links(result.value).map { taint(it.location) }
  end

  private

  def links(node)
    nested = node.compact_child_nodes.flat_map { links(it) }
    node.class.method_defined?(:receiver) && bare?(node.receiver) ? [node.receiver, *nested] : nested
  end

  def bare?(link)
    link.is_a?(CallNode) && link.receiver.is_a?(SelfNode) && !link.arguments && !link.block
  end

  def taint(location)
    start = location.start_offset
    Kimera::Memoization::Range.new(start, start + location.length, PRIVILEGE, nil)
  end
end
