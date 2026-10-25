# frozen_string_literal: true

require "prism"
require_relative "../parsing/syntax"

module Kimera
  module Execution
  end
end

class Kimera::Execution::PendingAutoload
  OPENED = [Prism::ClassNode, Prism::ModuleNode].freeze

  def initialize(file)
    @file = file
  end

  def fire! = opened(Kimera::Syntax.parse(File.read(@file, encoding: Encoding::UTF_8)).value, []).each { resolve(it) }

  private

  def opened(node, outer)
    inside = ->(path) { node.compact_child_nodes.flat_map { |child| opened(child, path) } }
    return inside.call(outer) unless OPENED.any? { |kind| node.is_a?(kind) }
    path = [*outer, *node.constant_path.full_name_parts.reject(&:empty?)]
    [path, *inside.call(path)]
  end

  def resolve(path)
    path.reduce(Object) do |namespace, part|
      break unless namespace.is_a?(Module) && namespace.const_defined?(part, false)
      namespace.const_get(part)
    end
  end
end
