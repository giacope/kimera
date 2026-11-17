# frozen_string_literal: true

require_relative "../parsing/syntax"
require_relative "../rewrite/ast_walk"

class Kimera::SyntaxGuard
  REASONS = {
    match_write_node: "a named capture is called before it binds, and guard branches change that call",
    defined_node: "defined? inspects its argument's syntax rather than evaluating its guards",
    flip_flop_node: "a flip-flop's integer endpoints must remain literals, not guarded expressions"
  }.freeze

  def initialize(source)
    @source = source
  end

  def reasons(node)
    guarded.filter_map do |guard|
      "#{REASONS.fetch(guard.type)} (evaluate with reload)" if affects?(guard, node.location)
    end
      .first(1)
  end

  private

  def guarded
    @_guarded ||=
      begin
        root = Kimera::Syntax.parse(@source).value
        Kimera::Rewrite::AstWalk.new(root).nodes.select { |node| guarded?(node) }
      end
  end

  def guarded?(node)
    return called?(node.call, node.targets.map(&:name)) if node.type == :match_write_node
    REASONS.key?(node.type)
  end

  def affects?(guard, location)
    span = (guard.type == :defined_node ? guard.value : guard).location
    if guard.type == :match_write_node
      (location.start_offset...location.end_offset).overlap?(span.start_offset...span.end_offset)
    else
      location.start_offset >= span.start_offset && location.end_offset <= span.end_offset
    end
  end

  def called?(node, names)
    return true if node.type == :call_node && node.variable_call? && names.include?(node.name)
    node.compact_child_nodes.any? { |child| called?(child, names) }
  end
end
