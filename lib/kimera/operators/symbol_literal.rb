# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::SymbolLiteral < Kimera::Operators::Base
  SUFFIX = "__kimera__"

  class << self
    def key = "symbol_literal"
  end

  def variants(node, **)
    return unless node.is_a?(SymbolNode)
    return if node.location.slice.end_with?(":")
    name = node.unescaped
    return if name.empty?
    tagged(name)
  end

  private

  def tagged(name)
    stem = name[0, 20]
    solo(":#{stem} => :#{stem}#{SUFFIX}", "symbol_literal", value: "#{name}#{SUFFIX}")
  end
end
