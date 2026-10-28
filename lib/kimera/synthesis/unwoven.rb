# frozen_string_literal: true

require_relative "../rewrite/ast_walk"
require_relative "../rewrite/numbered_params"
require_relative "../scribe/nodes"
require_relative "outline"

class Kimera::Unwoven
  include Kimera::Scribe::Nodes

  RUNTIME = %i[active? privatize].freeze

  def initialize(tree)
    @tree = tree
  end

  def keeps?(definitions) = definitions.all? { |definition| kept?(definition) }

  private

  def kept?(definition)
    woven = woven(definition)
    woven && Kimera::Outline.new(off(woven)).shape == Kimera::Outline.new(definition).shape
  end

  def woven(definition)
    line = definition.location.start_line
    defined.find { |node| node.name == definition.name && node.location.start_line == line }
  end

  def defined
    @_defined ||=
      [].tap do |found|
        Kimera::Rewrite::AstWalk.new(Kimera::Rewrite::NumberedParams.new(@tree).normalize).visit do |node|
          found << node if node.type == :def_node
        end
      end
  end

  def off(node) = Kimera::Rewrite::AstWalk.new(node).rebuild { |rebuilt, original| unguarded(rebuilt, original) }

  def unguarded(rebuilt, original)
    return side(rebuilt) if guard?(rebuilt)
    return rebuilt unless rebuilt.type == :statements_node
    pairs = rebuilt.body.zip(original.body).reject { |node, was| runtime?(node) || probe?(was) }
    rebuilt.copy(body: pairs.flat_map { |node, _| node.type == :statements_node ? node.body : [node] })
  end

  def side(guard) = statements(guard.subsequent&.statements&.body || [])

  def guard?(node) = node.type == :if_node && runtime?(node.predicate)

  def probe?(node) = guard?(node) && [node.statements, node.subsequent&.statements].all? { |each| empty?(each) }

  def empty?(statements)
    body = statements&.body || []
    body.one? && (body.first.type == :nil_node || probe?(body.first))
  end

  def runtime?(node)
    receiver = node.receiver if node.type == :call_node
    receiver&.type == :constant_path_node && receiver.name == :RUNTIME && RUNTIME.include?(node.name)
  end
end
