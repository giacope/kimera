# frozen_string_literal: true

require_relative "../parsing/syntax"
require_relative "../parsing/unescaped"

class Kimera::Outline
  LOOSE = %i[forced_utf8_encoding? binary? decimal? octal? hexadecimal? symbol_keys?].freeze
  SKIPPED = %i[node_id location locals].freeze

  def initialize(node)
    @node = node
  end

  def shape = traced(@node)

  private

  def traced(value)
    return value.map { |item| traced(item) } if value.is_a?(Array)
    return value unless value.is_a?(Kimera::Syntax::Node)
    lone = lone(value)
    lone ? traced(lone) : node(value)
  end

  def node(node)
    type = node.type
    return [:string, Kimera::Unescaped.new(node).text] if type == :string_node
    parts = joined(node.parts) if type == :interpolated_string_node
    return parts.first if parts&.one? && text?(parts.first)
    [type, *flags(node), *fields(node)]
  end

  def lone(node) = single(node.type == :statements_node ? node : inner(node))

  def single(body) = (body.body.first if body&.type == :statements_node && body.body.one?)

  def inner(node)
    return node.body if node.type == :parentheses_node
    node.statements if node.type == :embedded_statements_node
  end

  def flags(node) = (node.class.instance_methods(false).grep(/\?\z/) - LOOSE).sort.map { [it, node.public_send(it)] }

  def fields(node)
    kept = node.deconstruct_keys(nil).except(*SKIPPED).reject { |field, _| field.end_with?("_loc") }
    kept.map { |field, value| [field, field == :parts ? joined(value) : traced(value)] }
  end

  def joined(parts)
    runs = pieces(parts).chunk_while { |left, right| text?(left) && text?(right) }
    runs.map { |run| text?(run.first) ? [:string, run.sum("", &:last)] : run.first }
  end

  def pieces(parts)
    parts.flat_map { |part| part.type == :interpolated_string_node ? part.parts : [part] }.map { traced(it) }
  end

  def text?(piece) = piece.first == :string
end
