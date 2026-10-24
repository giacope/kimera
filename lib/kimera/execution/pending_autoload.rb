# frozen_string_literal: true

require "prism"
require_relative "../parsing/syntax"

module Kimera
  module Execution
  end
end

# A file an autoload names (`autoload :Table, "reg/table"`) loads when the
# suite first refers to its constant, often after the overlay is in place. Had
# the overlay been evaluated whole, opening the class would fire the autoload,
# and the overlay's own class body would then run a second time over the one
# the file just ran (kramdown's `@@parsers = {}` emptied its parser registry).
# Firing that autoload first loads the file as written, once, so the overlay
# can be trimmed to the methods it guards.
class Kimera::Execution::PendingAutoload
  OPENED = [Prism::ClassNode, Prism::ModuleNode].freeze
  NOT_INHERITED = false

  def initialize(file)
    @file = file
  end

  def fire!
    opened(Kimera::Syntax.parse(File.read(@file, encoding: Encoding::UTF_8)).value, []).any? { |path| fired?(path) }
  end

  private

  def opened(node, outer)
    return [] if node.is_a?(Prism::DefNode)
    inside = ->(path) { node.compact_child_nodes.flat_map { |child| opened(child, path) } }
    return inside.call(outer) unless OPENED.any? { |kind| node.is_a?(kind) }
    path = [*outer, *node.constant_path.full_name_parts.reject(&:empty?)]
    [path, *inside.call(path)]
  end

  def fired?(path)
    *outer, name = path
    owner = outer.reduce(Object) { |namespace, part| settled(namespace, part) || (return false) }
    feature = owner.autoload?(name, NOT_INHERITED)
    feature && names?(feature) && !owner.const_get(name, false).nil?
  end

  def settled(namespace, part)
    return unless namespace.const_defined?(part, false) && !namespace.autoload?(part, NOT_INHERITED)
    value = namespace.const_get(part, false)
    value if value.is_a?(Module)
  end

  def names?(feature)
    _kind, path = $LOAD_PATH.resolve_feature_path(feature)
    path && File.realpath(path) == File.realpath(@file)
  rescue SystemCallError, LoadError
    false
  end
end
