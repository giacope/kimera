# frozen_string_literal: true

require_relative "../rewrite/ast_walk"
require_relative "guardrail_value_objects"

class Kimera::SpliceReopening
  FACTORIES = Kimera::GuardrailValueObjects::VALUE_OBJECT_FACTORIES
  LEXICAL = "(is_a?(::Module) ? self : ::Object)"

  Assignment =
    Data.define(:scope, :name, :value, :location) do
      def edit = [location.expression.begin_pos, value.location.begin.begin_pos, header, []]

      def header
        owner = base
        "#{constant} = (#{owner}.const_defined?(:#{name}, false) ? #{owner}.const_get(:#{name}) : " \
          "#{factory}); #{constant}.class_eval "
      end

      def constant = location.expression.begin.join(location.name).source

      def factory = value.children.first.location.expression.source

      def base
        return LEXICAL unless scope
        scope.type == :cbase ? "::Object" : scope.location.expression.source
      end
    end

  def initialize(map)
    @map = map
  end

  def edits = constants.map(&:edit)

  private

  def constants
    found = []
    Kimera::Rewrite::AstWalk.visit(@map.ast) { |node| found << assignment(node) if reopenable?(node) }
    found
  end

  def assignment(node) = Assignment.new(*node, node.location)

  def reopenable?(node)
    return false unless node.type == :casgn
    value = node.children.last
    value.is_a?(Parser::AST::Node) && value.type == :block && factory?(value.children.first)
  end

  def factory?(call)
    receiver, selector = call.children
    call.type == :send && receiver.is_a?(Parser::AST::Node) && receiver.type == :const &&
      FACTORIES[receiver.children.last] == selector
  end
end
