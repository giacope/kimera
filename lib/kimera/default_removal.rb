# frozen_string_literal: true

require_relative "memo_guard"
require_relative "memoization"
require_relative "support/syntax"
require_relative "support/syntax_types"

class Kimera::DefaultRemoval
  include Kimera::SyntaxTypes

  OPERATOR = "default_argument"
  REBINDS = "default removal rebinds the positional arguments around it (evaluate with reload)"
  BLOCK = "default removal in a block binds an omitted argument to nil (evaluate with reload)"
  REORDERS = "default removal skips an earlier default the warm guard would evaluate (evaluate with reload)"
  INERT = [IntegerNode, FloatNode, StringNode, SymbolNode, NilNode, TrueNode, FalseNode, LocalVariableReadNode].freeze
  CALLABLES = [DefNode, LambdaNode, BlockNode].freeze

  class << self
    def exemptions(source) = signatures(source).flat_map(&:exemptions)

    def ranges(source) = signatures(source).flat_map(&:ranges)

    private

    def signatures(source)
      result = Kimera::Syntax.parse(source)
      result.failure? ? [] : collect(result.value, [])
    end

    def collect(node, found)
      found << new(parameters(node), node.is_a?(Kimera::SyntaxTypes::BlockNode)) if callable?(node)
      node.compact_child_nodes.each { collect(it, found) }
      found
    end

    def callable?(node) = CALLABLES.any? { node.is_a?(it) } && node.parameters

    def parameters(callable)
      parameters = callable.parameters
      parameters.is_a?(Kimera::SyntaxTypes::BlockParametersNode) ? parameters.parameters : parameters
    end
  end

  def initialize(parameters, block)
    @parameters = parameters
    @block = block
  end

  def exemptions
    return [] unless @parameters.is_a?(ParametersNode)
    optionals.each_index.reject { parses?(it) }.map { Kimera::MemoGuard::Exemption.new(optionals[it].location, OPERATOR) }
  end

  def ranges
    return [] unless @parameters.is_a?(ParametersNode)
    positional + keyword
  end

  private

  def optionals = @parameters.optionals

  def keywords = @parameters.keywords.grep(OptionalKeywordParameterNode)

  def parses?(index) = index.zero? || (index == optionals.size - 1 && !@parameters.rest)

  def positional
    optionals.each_index.filter_map do |index|
      reason = @block ? BLOCK : REBINDS
      taint(optionals[index], reason) if parses?(index) && (@block || index.positive?)
    end
  end

  def keyword
    keywords.each_with_index.filter_map do |parameter, index|
      taint(parameter, REORDERS) unless (optionals + keywords.first(index)).all? { INERT.include?(it.value.class) }
    end
  end

  def taint(parameter, reason)
    location = parameter.location
    start = location.start_offset
    Kimera::Memoization::Range.new(start, start + location.length, reason, nil)
  end
end
