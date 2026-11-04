# frozen_string_literal: true

require_relative "../scribe"
require_relative "../scribe/nodes"
require_relative "../rewrite/ast_walk"
require_relative "../rewrite/directive"
require_relative "guardrail_dispatch"
require_relative "guardrail_factories"
require_relative "line_pad"
require_relative "readback"
require_relative "source_map"

class Kimera::Guardrail
  include Kimera::GuardrailDispatch
  include Kimera::GuardrailFactories
  include Kimera::Scribe::Nodes

  ANCHOR = ->(node) { [node.location.start_offset, node.location.end_offset, node.type.to_s] }

  class Patch
    def initialize(anchor, directive)
      @anchor = anchor
      @directive = directive
    end

    def apply(rebuilt, original)
      return rebuilt unless ANCHOR.call(original) == anchor
      directive.apply(rebuilt)
    end

    private

    attr_reader :anchor, :directive
  end

  def initialize(map, points)
    @map = map
    @points = points
  end

  def tree = @_tree ||= transform(@map.ast)

  def rewrite(node)
    woven = transform(node)
    [Kimera::LinePad.new(node.slice).fits(Kimera::Scribe.new(woven), Kimera::Readback.new(woven)), activated(woven)]
  end

  def bake(point, directive)
    node = point.anchored(nodes) { return }
    overlay(ANCHOR.call(node), directive)
  end

  def changes(point, directive)
    node = point.anchored(nodes) { return }
    patch = Patch.new(ANCHOR.call(node), directive)
    changed = []
    Kimera::Rewrite::AstWalk.new(@map.ast).rebuild do |rebuilt, original|
      patch.apply(rebuilt, original).tap { |node| changed << [original, node] unless node.equal?(original) }
    end
    changed
  end

  private

  def activated(node)
    found = []
    Kimera::Rewrite::AstWalk.new(node).visit { |visited| found << activation(visited) }
    found.compact
  end

  def transform(node) = weave(node).fetch(0)

  def activation(node)
    return unless node.type == :call_node && node.name == :active? && runtime?(node.receiver)
    node.arguments.arguments.first.value
  end

  def runtime?(node) = node&.type == :constant_path_node && node.name == :RUNTIME && node.parent&.name == :Kimera

  def nodes
    {}.tap { |found| Kimera::Rewrite::AstWalk.new(@map.ast).visit { |node| found[ANCHOR.call(node)] = node } }
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

  def points(node) = (@_anchored ||= anchored(nodes)).fetch(ANCHOR.call(node), [])

  def anchored(nodes)
    placed = @points.map { |point| [point.anchored(nodes) { next }, point] }.select(&:first)
    placed.group_by { |node, _point| ANCHOR.call(node) }.transform_values { |pairs| pairs.map(&:last) }
  end
end
