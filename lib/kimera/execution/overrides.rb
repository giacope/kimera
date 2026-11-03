# frozen_string_literal: true

require_relative "../parsing/syntax"
require_relative "overrides/held"
require_relative "redefinition"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Overrides
  SINGLETON = Kernel.instance_method(:singleton_class)
  VISITS = {
    Prism::ClassNode => :nested, Prism::ModuleNode => :nested, Prism::SingletonClassNode => :lifted,
    Prism::DefNode => :owned, Prism::BlockNode => :skipped, Prism::LambdaNode => :skipped
  }.freeze

  def initialize(file, source)
    @given = file
    @source = source
  end

  def keep
    held = defined.flat_map { |holder, name, span| elsewhere(holder, name, span) }
    [yield, held.flat_map { |entry| entry.restored(file) }]
  end

  private

  def file = @_file ||= Kimera::Execution::Origin.new(@given).canonical

  def defined = visit(Kimera::Syntax.parse(@source).value, [], :instance)

  def visit(node, scope, side)
    handler = VISITS[node.class]
    return __send__(handler, node, scope, side) if handler
    node.compact_child_nodes.flat_map { |child| visit(child, scope, side) }
  end

  def nested(node, scope, _side)
    body = node.body
    body ? visit(body, [*scope, node.constant_path.slice], :instance) : []
  end

  def lifted(node, scope, _side)
    body = node.body
    body && node.expression.is_a?(Prism::SelfNode) ? visit(body, scope, :singleton) : []
  end

  def skipped(_node, _scope, _side) = []

  def owned(node, scope, side)
    holder = resolve(scope) { return [] }
    receiver = node.receiver
    return [] unless receiver.nil? || receiver.is_a?(Prism::SelfNode)
    owner = side == :singleton || receiver ? SINGLETON.bind_call(holder) : holder
    [[owner, node.name, node.location]]
  end

  def resolve(scope)
    scope.empty? ? Object : Object.const_get(scope.join("::").delete_prefix("::"))
  rescue NameError
    yield
  end

  def elsewhere(holder, name, span)
    redefinition = Kimera::Execution::Redefinition.new(holder, name)
    redefinition.held(Kimera::Execution::Overrides::Held, span) { |found| found.owner == holder && !here?(found) }
  end

  def here?(method) = Kimera::Execution::Origin.new(method.source_location&.first).canonical == file
end
