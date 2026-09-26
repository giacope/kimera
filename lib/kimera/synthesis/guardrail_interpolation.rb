# frozen_string_literal: true

module Kimera
  module GuardrailInterpolation
    INTERPOLATING = %i[dstr dsym regexp xstr].freeze

    private

    def type?(node, type)
      node.is_a?(Parser::AST::Node) && node.type == type
    end

    def string?(node)
      type?(node, :str)
    end

    def empty?(node)
      string?(node) && node.children.first == ""
    end

    def interpolation?(node)
      type?(node, :begin)
    end

    def flatten(node)
      spliced = node.children.flat_map { |child| type?(child, :dstr) ? child.children : [child] }
      spliced = merge(spliced) if spliced.any? { |child| interpolation?(child) }
      node.updated(nil, spliced)
    end

    def merge(children)
      children.each_with_object([]) { |child, items| append(items, child) }
    end

    def append(items, child)
      previous = items.last
      return items << child unless string?(child) && string?(previous)
      items[-1] = ast(:str, previous.children.first + child.children.first)
    end

    def prune(node)
      Kimera::Rewrite::AstWalk.rebuild(node) do |rebuilt, _original|
        INTERPOLATING.include?(rebuilt.type) ? filter(rebuilt) : rebuilt
      end
    end

    def filter(node)
      kept = node.children.reject { |child| empty?(child) }
      return ast(:str, "") if node.type == :dstr && kept.empty?
      collapse(node, kept)
    end

    def collapse(node, kept)
      first = kept.first
      return first if node.type == :dstr && kept.one? && %i[str dstr].include?(first.type)
      node.updated(nil, kept)
    end
  end
end
