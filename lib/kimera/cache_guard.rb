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
  Exemption = Kimera::MemoGuard::Exemption

  def initialize(method)
    @method = method
  end

  def exemptions = nodes.filter_map { |node| exempt(node) }.flatten

  private

  def exempt(node)
    cache = CONDITIONALS.include?(node.class) && guarded(node)
    return unless cache && stores.key?(cache)
    [
      Exemption.new(node.location, Kimera::MemoGuard::CONDITIONAL),
      *stores.fetch(cache).map { Exemption.new(it.location, STATEMENT_DELETION) }
    ]
  end

  def nodes = @_nodes ||= walk(@method)

  def walk(node) = [node, *node.compact_child_nodes.flat_map { walk(it) }]

  def stores = @_stores ||= nodes.select { lookup(it, :[]=) }.group_by { cache(it) }

  def guarded(node)
    returned = early(node)
    name = local(returned)
    cache = lookup(returned, :[]) || cached[name]
    cache if cache && mentions?(node.predicate, cache, name)
  end

  def early(node)
    values = returned(node)&.arguments&.arguments
    values&.size == 1 ? values.first : nil
  end

  def returned(node)
    body = node.statements&.body
    body.first if body&.size == 1 && body.first.is_a?(Kimera::SyntaxTypes::ReturnNode)
  end

  def cached
    @_cached ||= nodes.grep(Kimera::SyntaxTypes::LocalVariableWriteNode)
      .filter_map { |write| [write.name, lookup(write.value, :[])] if lookup(write.value, :[]) }.to_h
  end

  def local(node) = node.is_a?(Kimera::SyntaxTypes::LocalVariableReadNode) ? node.name : nil

  def mentions?(predicate, cache, name)
    walk(predicate).any? { |node| (name && local(node) == name) || LOOKUPS.any? { lookup(node, it) == cache } }
  end

  def lookup(node, name) = node.is_a?(Kimera::SyntaxTypes::CallNode) && node.name == name ? cache(node) : nil

  def cache(node)
    receiver = node.receiver
    receiver.name if CACHES.include?(receiver.class)
  end
end
