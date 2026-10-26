# frozen_string_literal: true

require "prism"
require_relative "../parsing/syntax"

module Kimera
  module Execution
  end
end

class Kimera::Execution::Definitions
  CONSTANTS = [
    Prism::ConstantWriteNode, Prism::ConstantPathWriteNode, Prism::ConstantOrWriteNode, Prism::ConstantPathOrWriteNode
  ].freeze
  BODIES = [Prism::ClassNode, Prism::ModuleNode, Prism::SingletonClassNode].freeze
  LOADING = %i[require require_relative autoload].freeze
  DECLARING = %i[
    private protected public module_function private_constant public_constant private_class_method
    public_class_method attr_reader attr_writer attr_accessor alias_method
  ].freeze
  NAMES = [Prism::SymbolNode, Prism::StringNode, Prism::DefNode].freeze

  def initialize(source)
    @source = source
  end

  def only? = defining?(Kimera::Syntax.parse(@source).value.statements)

  private

  def defining?(body) = body.nil? || (body.is_a?(Prism::StatementsNode) && body.body.all? { |node| definition?(node) })

  def definition?(node)
    return defining?(node.body) if BODIES.any? { |kind| node.is_a?(kind) }
    [Prism::DefNode, Prism::AliasMethodNode, *CONSTANTS].any? { |kind| node.is_a?(kind) } ||
      (node.is_a?(Prism::CallNode) && node.receiver.nil? && declaring?(node))
  end

  def declaring?(call) = LOADING.include?(call.name) || (DECLARING.include?(call.name) && named?(call))

  def named?(call) = Array(call.arguments&.arguments).all? { |name| NAMES.any? { |kind| name.is_a?(kind) } }
end
