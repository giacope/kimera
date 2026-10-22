# frozen_string_literal: true

require_relative "../scribe"
require_relative "../scribe/nodes"
require_relative "../rewrite/ast_walk"
require_relative "../rewrite/directive"
require_relative "guardrail_dispatch"
require_relative "guardrail_factories"
require_relative "source_map"

class Kimera::Guardrail
  include Kimera::GuardrailDispatch
  include Kimera::GuardrailFactories
  include Kimera::Scribe::Nodes

  ANCHOR = ->(node) { [node.location.start_offset, node.location.end_offset, node.type.to_s] }

  Patch =
    Data.define(:anchor, :directive) do
      def apply(rebuilt, original)
        return rebuilt unless ANCHOR.call(original) == anchor
        Kimera::Rewrite::Directive.new(directive).apply(rebuilt)
      end
    end

  def initialize(map, points)
    @map = map
    @points = points
  end

  def tree = @_tree ||= transform(@map.ast)

  def applied = activated(tree)

  def rewrite(node)
    woven = transform(node)
    [Kimera::Scribe.new(woven).source, activated(woven)]
  end

  def activated(node)
    found = []
    Kimera::Rewrite::AstWalk.new(node).visit { |visited| found << activation(visited) }
    found.compact
  end

  def transform(node) = weave(node).first

  def bake(point, directive)
    location = point.location
    target = [location.start_offset, location.finish, point.node_type]
    overlay(target, directive) if anchors.include?(target)
  end

  private

  def activation(node)
    return unless node.type == :call_node && node.name == :active? && runtime?(node.receiver)
    node.arguments.arguments.first.value
  end

  def runtime?(node) = node&.type == :constant_path_node && node.name == :RUNTIME && node.parent&.name == :Kimera

  def anchors
    Set.new.tap { |found| Kimera::Rewrite::AstWalk.new(@map.ast).visit { |node| found << ANCHOR.call(node) } }
  end

  def weave(node)
    fields = node.deconstruct_keys(nil).filter_map { |field, value| [field, split(value)] if woven?(value) }.to_h
    woven = node.copy(**fields.transform_values(&:first))
    bare = node.copy(**fields.transform_values(&:last))
    [reopen(dispatch(woven, bare, points(node))), reopen(bare)]
  end

  def woven?(value) = value.is_a?(Kimera::Syntax::Node) || (value.is_a?(Array) && value.all?(Kimera::Syntax::Node))

  def split(value)
    if value.is_a?(Array)
      value.map do |item|
        weave(item)
      end.transpose.then { |pair| pair.empty? ? [[], []] : pair }
    else
      weave(value)
    end
  end

  def overlay(target, directive)
    patch = Patch.new(target, directive)
    Kimera::Rewrite::AstWalk.new(@map.ast).rebuild do |rebuilt, original|
      reopen(patch.apply(rebuilt, original))
    end
  end

  def points(node) = (@_anchored ||= group(@points)).fetch(ANCHOR.call(node), [])
end
