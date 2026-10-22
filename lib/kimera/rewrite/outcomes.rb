# frozen_string_literal: true

require_relative "../scribe"
require_relative "ast_walk"
require_relative "conditions"
require_relative "directive"
require_relative "numbered_params"

class Kimera::Rewrite::Outcomes
  NUMERIC = Kimera::Scribe::Numeral::TYPES
  FLAG = /\A(?!forced_).*\?\z/
  INCIDENTAL = %i[node_id location locals].freeze

  def initialize(source)
    @source = source
  end

  def distinct(node, variants, &)
    variants.each_with_object([]) do |variant, kept|
      kept << variant if kept.none? { |earlier| program(node, earlier, &) == program(node, variant, &) }
    end
  end

  def writable(node, variants)
    found = nodes[key(node)]
    variants.reject { |variant| misread?(found, yield(variant)) }
  end

  private

  def misread?(node, directive)
    applied = Kimera::Rewrite::Directive.new(directive).apply(node)
    Kimera::Rewrite::Conditions.new(applied, tested: tested[node]).misread?
  rescue StandardError
    false
  end

  def tested = @_tested ||= Kimera::Rewrite::Conditions.new(tree).places

  def tree = @_tree ||= Kimera::Rewrite::NumberedParams.new(Kimera::Scribe.parse(@source)).normalize

  def program(node, variant)
    (@_programs ||= {}.compare_by_identity)[variant] ||= rendered(node, yield(variant))
  end

  def rendered(node, directive)
    found = nodes[key(node)]
    (found && form(Kimera::Rewrite::Directive.new(directive).apply(found))) || directive
  rescue StandardError
    directive
  end

  def nodes
    @_nodes ||= {}.tap { |found| Kimera::Rewrite::AstWalk.new(tree).visit { |node| found[key(node)] ||= node } }
  rescue StandardError
    @_nodes ||= {}
  end

  def key(node)
    location = node.location
    [location.start_offset, location.end_offset, node.type]
  end

  def form(node)
    inner = bare(node)
    number = value(inner)
    number ? [Numeric, number.inspect] : [inner.type, *flags(inner), *fields(inner)]
  end

  def flags(node) = node.class.instance_methods(false).grep(FLAG).sort.map { |flag| node.public_send(flag) }

  def fields(node)
    node.deconstruct_keys(nil).except(*INCIDENTAL).filter_map do |field, value|
      [field, part(value)] unless field.end_with?("_loc")
    end
  end

  def part(value)
    case value
    when Kimera::Syntax::Node then form(value)
    when Array then value.map { |item| part(item) }
    else value
    end
  end

  def value(node)
    return node.value if NUMERIC.include?(node.type)
    number = negated?(node) && value(bare(node.receiver))
    -number if number
  end

  def negated?(node) = node.type == :call_node && node.name == :-@ && node.receiver && !(node.arguments || node.block)

  def bare(node)
    inner = contents(node)
    inner&.one? ? bare(inner.first) : node
  end

  def contents(node)
    case node.type
    when :statements_node then node.body
    when :parentheses_node then node.body && contents(node.body)
    end
  end
end
