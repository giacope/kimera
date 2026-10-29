# frozen_string_literal: true

require_relative "../../parsing/syntax"

module Kimera
  module Execution
  end
end

class Kimera::Execution::BlockMethods; end

class Kimera::Execution::BlockMethods::Survey
  Scope =
    Data.define(:opening, :usings) do
      def to_s = "#{opening}#{usings.join}"
      def refined(using) = with(usings: [*usings, using])
    end
  OPENERS = { Prism::ClassNode => "class", Prism::ModuleNode => "module" }.freeze
  BLOCKS = [Prism::BlockNode, Prism::LambdaNode].freeze

  def initialize(source)
    @source = source
  end

  def sites
    root = Kimera::Syntax.parse(@source).value
    found, = walk(root, [Scope.new(@source.byteslice(0, root.location.start_offset), [])], root)
    found
  end

  private

  def walk(node, nesting, scope)
    return [defined(node, nesting, scope), nesting] if node.is_a?(Prism::DefNode)
    return [[], refined(node, nesting)] if using?(node)
    keyword = OPENERS[node.class]
    return [opened(node, [*nesting, Scope.new("#{keyword} #{node.constant_path.slice}; ", [])]), nesting] if keyword
    descend(node.compact_child_nodes, nesting, BLOCKS.include?(node.class) ? node : scope)
  end

  def descend(children, nesting, scope)
    children.reduce([[], nesting]) do |(found, outer), child|
      sites, after = walk(child, outer, scope)
      [found + sites, after]
    end
  end

  def using?(node) = node.is_a?(Prism::CallNode) && node.name == :using && node.receiver.nil?

  def refined(node, nesting) = [*nesting[...-1], nesting.last.refined("#{node.slice}; ")]

  def defined(node, nesting, scope) = BLOCKS.include?(scope.class) && node.receiver.nil? ? [site(node, nesting)] : []

  def opened(node, nesting)
    body = node.body
    return [] unless body
    found, = walk(body, nesting, node)
    found
  end

  def site(node, nesting)
    location = node.location
    file, *openers = nesting.map(&:to_s)
    Kimera::Execution::BlockMethods::Site
      .new(node.name, location.start_line, [location.start_offset, location.end_offset], file, openers, node.slice)
  end
end
