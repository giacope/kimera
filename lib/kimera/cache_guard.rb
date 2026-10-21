# frozen_string_literal: true

require_relative "memo_guard"

class Kimera::CacheGuard
  STATEMENT_DELETION = "statement_deletion"
  CACHES = [
    Kimera::SyntaxTypes::InstanceVariableReadNode,
    Kimera::SyntaxTypes::ClassVariableReadNode,
    Kimera::SyntaxTypes::GlobalVariableReadNode
  ].freeze
  CONDITIONALS = [Kimera::SyntaxTypes::IfNode, Kimera::SyntaxTypes::UnlessNode].freeze
  LOOKUPS = %i[[] key? include? has_key? member?].freeze
  LOCAL = Kimera::SyntaxTypes::LocalVariableReadNode
  Exemption = Kimera::MemoGuard::Exemption

  def initialize(method)
    @method = method
  end

  def exemptions
    nodes = walk(@method)
    stores = nodes.select { lookup(it, :[]=) }.group_by { lookup(it, :[]=) }
    locals = nodes.grep(Kimera::SyntaxTypes::LocalVariableWriteNode).to_h { [it.name, lookup(it.value, :[])] }
    nodes.filter_map { |node| exempt(node, stores, guarded(node, locals)) }.flatten
  end

  private

  def exempt(node, stores, cache)
    return unless cache && stores.key?(cache)
    [
      Exemption.new(node.location, Kimera::MemoGuard::CONDITIONAL),
      *stores.fetch(cache).map { Exemption.new(it.location, STATEMENT_DELETION) }
    ]
  end

  def guarded(node, locals)
    returned = early(node) if CONDITIONALS.include?(node.class)
    name = returned.name if returned.is_a?(LOCAL)
    cache = returned && (lookup(returned, :[]) || locals[name])
    cache if cache && mentions?(node.predicate, cache, name)
  end

  def early(node)
    returned, *rest = node.statements&.body
    return if rest.any? || !returned.is_a?(Kimera::SyntaxTypes::ReturnNode)
    value, *more = returned.arguments&.arguments
    value if more.empty?
  end

  def mentions?(predicate, cache, name)
    walk(predicate).any? do |node|
      (node.is_a?(LOCAL) && name && node.name == name) || LOOKUPS.any? { lookup(node, it) == cache }
    end
  end

  def walk(node) = [node, *node.compact_child_nodes.flat_map { walk(it) }]

  def lookup(node, name)
    receiver = node.receiver if node.is_a?(Kimera::SyntaxTypes::CallNode) && node.name == name
    receiver.name if CACHES.include?(receiver.class)
  end
end
