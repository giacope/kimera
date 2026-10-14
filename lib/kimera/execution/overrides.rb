# frozen_string_literal: true

require "prism"
require_relative "redefinition"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Overrides
  Held = Data.define(:holder, :name, :definition, :visibility)
  LOOKUP = Module.instance_method(:instance_method)
  SINGLETON = Kernel.instance_method(:singleton_class)
  VISITS = {
    Prism::ClassNode => :nested, Prism::ModuleNode => :nested, Prism::SingletonClassNode => :lifted,
    Prism::DefNode => :owned, Prism::BlockNode => :skipped, Prism::LambdaNode => :skipped
  }.freeze

  attr_reader :displaced

  def initialize(file, source)
    @given = file
    @source = source
    @displaced = []
  end

  def keep
    held = defined.filter_map { |holder, name| elsewhere(holder, name) }
    yield.tap { @displaced = held.filter_map { |entry| restore(entry) } }
  end

  private

  def file = @_file ||= Kimera::Execution::Redefinition.canonical(@given)

  def defined
    found = []
    visit(Prism.parse(@source).value, [], :instance, found)
    found.compact
  end

  def visit(node, scope, side, found)
    handler = VISITS[node.class]
    return __send__(handler, node, scope, side, found) if handler
    node.compact_child_nodes.each { |child| visit(child, scope, side, found) }
  end

  def nested(node, scope, _side, found)
    body = node.body
    visit(body, [*scope, node.constant_path.slice], :instance, found) if body
  end

  def lifted(node, scope, _side, found)
    body = node.body
    visit(body, scope, :singleton, found) if body && node.expression.is_a?(Prism::SelfNode)
  end

  def skipped(_node, _scope, _side, found) = found

  def owned(node, scope, side, found)
    holder = resolve(scope)
    receiver = node.receiver
    return unless holder && (receiver.nil? || receiver.is_a?(Prism::SelfNode))
    found << [side == :singleton || receiver ? SINGLETON.bind_call(holder) : holder, node.name]
  end

  def resolve(scope)
    scope.empty? ? Object : Object.const_get(scope.join("::").delete_prefix("::"))
  rescue NameError
    nil
  end

  def elsewhere(holder, name)
    found = lookup(holder, name)
    return unless found && found.owner == holder && !here?(found)
    Held.new(holder, name, found, Kimera::Execution::Redefinition.visibility(holder, name))
  end

  def restore(entry)
    holder, name, kept, visibility = entry.deconstruct
    fresh = lookup(holder, name)
    return unless fresh && here?(fresh)
    Kimera::Execution::Redefinition.redefine(holder, name, kept, visibility)
    entry.with(definition: fresh)
  end

  def here?(method) = Kimera::Execution::Redefinition.canonical(Kimera::Execution::Redefinition.source(method)) == file

  def lookup(holder, name)
    LOOKUP.bind_call(holder, name)
  rescue NameError
    nil
  end
end
