# frozen_string_literal: true

require "prism"

# A Prism tree up to how its source spelled it: no locations, a string however
# its parts were split, a number in any base. Two trees of one shape are the
# same program.
module TreeShape
  SPELLING = /\A(?:forced_\w+_encoding|frozen|mutable|binary|decimal|octal|hexadecimal)\?\z/

  module_function

  def of(node)
    case node
    when Prism::Node then string(node) || [node.type, *flags(node), *fields(node)]
    when Array then node.map { |item| of(item) }
    else node
    end
  end

  def flags(node)
    node.class.instance_methods(false).grep(/\?\z/).grep_v(SPELLING).sort.map { |flag| [flag, node.public_send(flag)] }
  end

  def fields(node)
    kept = node.deconstruct_keys(nil).except(:node_id, :location).reject { |field, _| field.end_with?("_loc") }
    kept.map { |field, value| [field, field == :parts ? parts(value) : of(value)] }
  end

  def string(node)
    return [:string, node.unescaped] if node.type == :string_node
    merged = parts(node.parts) if node.type == :interpolated_string_node
    merged.first if merged&.one? && text?(merged.first)
  end

  def parts(list)
    joined(
      list.flat_map do |part|
        part.type == :interpolated_string_node ? part.parts : [part]
      end.map { |part| piece(part) }
    )
  end

  def piece(part) = part.type == :string_node ? [:string, part.unescaped] : of(part)

  def joined(pieces)
    runs = pieces.chunk_while { |left, right| text?(left) && text?(right) }
    runs.map { |run| text?(run.first) ? [:string, run.sum("") { |piece| piece[1] }] : run.first }
  end

  def text?(piece) = piece.first == :string
end
