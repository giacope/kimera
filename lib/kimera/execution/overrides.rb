# frozen_string_literal: true

require_relative "../parsing/syntax"
require_relative "redefinition"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Overrides
  Held = Data.define(:holder, :name, :definition, :visibility, :lines)
  WRAPPED =
    "another file redefined its method around the one it replaced (a memoizer that holds that method), and the " \
      "warm overlay keeps that definition, which never calls the mutated one; so a mutant no test reached warm is " \
      "judged again in a fresh mirror against the tests near its file"
  LOOKUP = Module.instance_method(:instance_method)
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
    held = defined.filter_map { |holder, name, lines| elsewhere(holder, name, lines) }
    [yield, held.filter_map { |entry| restore(entry) }]
  end

  def revisit!(points, held)
    points.each do |point|
      line = point.location.start_line
      point.revisit!(WRAPPED) if point.safe? && held.any? { |entry| entry.lines.cover?(line) }
    end
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
    holder = resolve(scope)
    receiver = node.receiver
    return [] unless holder && (receiver.nil? || receiver.is_a?(Prism::SelfNode))
    location = node.location
    owner = side == :singleton || receiver ? SINGLETON.bind_call(holder) : holder
    [[owner, node.name, location.start_line..location.end_line]]
  end

  def resolve(scope)
    scope.empty? ? Object : Object.const_get(scope.join("::").delete_prefix("::"))
  rescue NameError
    nil
  end

  def elsewhere(holder, name, lines)
    found = lookup(holder, name)
    return unless found && found.owner == holder && !here?(found)
    Held.new(holder, name, found, Kimera::Execution::Redefinition.new(holder, name).visibility, lines)
  end

  def restore(entry)
    holder, name, kept, visibility = entry.deconstruct.first(4)
    fresh = lookup(holder, name)
    return unless fresh && here?(fresh)
    Kimera::Execution::Redefinition.new(holder, name).redefine(kept, visibility)
    entry.with(definition: fresh)
  end

  def here?(method) = Kimera::Execution::Origin.new(method.source_location&.first).canonical == file

  def lookup(holder, name)
    LOOKUP.bind_call(holder, name)
  rescue NameError
    nil
  end
end
