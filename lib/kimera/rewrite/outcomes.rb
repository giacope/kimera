# frozen_string_literal: true

require_relative "../support/unparse"
require_relative "conditions"
require_relative "directive"
require_relative "numbered_params"

class Kimera::Rewrite::Outcomes
  NUMERIC = %i[int float rational complex].freeze

  def initialize(source)
    @source = source
  end

  def distinct(location, variants, &)
    variants.each_with_object([]) do |variant, kept|
      kept << variant if kept.none? { |earlier| program(location, earlier, &) == program(location, variant, &) }
    end
  end

  def writable(location, variants)
    node = nodes[[location.start_offset, location.end_offset]]
    variants.reject { |variant| misread?(node, yield(variant)) }
  end

  private

  def misread?(node, directive)
    Kimera::Rewrite::Conditions.misread?(Kimera::Rewrite::Directive.apply(node, directive), tested: tested[node])
  rescue StandardError
    false
  end

  def tested = @_tested ||= Kimera::Rewrite::Conditions.places(tree)

  def tree = @_tree ||= Kimera::Rewrite::NumberedParams.normalize(Kimera::Unparse.parse(@source))

  def program(location, variant)
    programs[variant] ||= outcome(location, yield(variant))
  end

  def outcome(location, directive) = rendered(location, directive) || directive

  def programs = @_programs ||= {}.compare_by_identity

  def rendered(location, directive)
    node = nodes[[location.start_offset, location.end_offset]]
    node && form(Kimera::Rewrite::Directive.apply(node, directive))
  rescue StandardError
    nil
  end

  def nodes
    @_nodes ||= index(tree, {})
  rescue StandardError
    @_nodes = {}
  end

  def index(node, found)
    return found unless node.is_a?(Parser::AST::Node)
    expression = node.location&.expression
    found[[offsets[expression.begin_pos], offsets[expression.end_pos]]] ||= node if expression
    node.children.each { |child| index(child, found) }
    found
  end

  def offsets = @_offsets ||= @source.each_char.with_object([0]) { |char, table| table << (table.last + char.bytesize) }

  def form(node)
    return node unless node.is_a?(Parser::AST::Node)
    inner = bare(node)
    number = value(inner)
    number ? [Numeric, number.inspect] : [inner.type, *inner.children.map { form(it) }]
  end

  def value(node)
    receiver, selector, *arguments = node.children
    return receiver if NUMERIC.include?(node.type)
    number = selector == :-@ && arguments.empty? && value(bare(receiver))
    -number if number
  end

  def bare(node)
    inner = lone(node)
    inner ? bare(inner) : node
  end

  def lone(node)
    children = node.children
    children[0] if node.type == :begin && children.one?
  end
end
