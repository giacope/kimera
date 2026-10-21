# frozen_string_literal: true

require "prism"
require_relative "../support/syntax"

module Kimera
  module Execution
  end
end

# Whether a file's top level only defines (classes, modules, constants,
# requires), so evaluating it before the suite asks for it changes nothing
# but which definitions exist. A generator template or a script assigns or
# calls at the top level instead, and must not run inside the test process.
class Kimera::Execution::Definitions
  DEFINING = [
    Prism::ClassNode, Prism::ModuleNode, Prism::ConstantWriteNode, Prism::ConstantPathWriteNode,
    Prism::ConstantOrWriteNode, Prism::ConstantPathOrWriteNode, Prism::SingletonClassNode
  ].freeze
  LOADING = %i[require require_relative autoload].freeze

  def initialize(source)
    @source = source
  end

  def only?
    program = Kimera::Syntax.parse(@source).value
    Array(program.statements&.body).all? { |node| defining?(node) }
  end

  private

  def defining?(node)
    DEFINING.any? do |kind|
      node.is_a?(kind)
    end || (node.is_a?(Prism::CallNode) && node.receiver.nil? && LOADING.include?(node.name))
  end
end
