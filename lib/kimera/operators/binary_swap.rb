# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::BinarySwap < Kimera::Operators::Base
  def variants(node, **)
    return unless swappable?(node)
    name = node.name
    self.class::MUTATIONS[name].map { |to| swap(name, to) }
  end

  private

  def swappable?(node)
    return false unless node.is_a?(CallNode)
    return false unless arguments(node).length == 1
    self.class::MUTATIONS.key?(node.name)
  end

  def swap(name, to)
    Kimera::Operators::Variant.new(label: "#{name} => #{to}", directive: directive(self.class::DIRECTIVE, to: to.to_s))
  end
end
