# frozen_string_literal: true

require "prism"

# A Prism tree up to how its source spelled it: no locations, a string however
# its parts were split, a number in any base. Two trees of one shape are the
# same program. A string is its value as Ruby makes it: Prism reads the bytes
# in the file's encoding and flags the one an escape forces (`"\u{3042}"` is
# UTF-8 in a binary file, `"\xE3\x81\x82"` is not), so the flag is no spelling.
module TreeShape
  SPELLING = /\A(?:forced_\w+_encoding|frozen|mutable|binary|decimal|octal|hexadecimal)\?\z/
  FORCED = { forced_utf8_encoding?: Encoding::UTF_8, forced_binary_encoding?: Encoding::BINARY }.freeze

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
    kept.map { |field, value| [field, field == :parts ? parts(value) : field(node, field, value)] }
  end

  def field(node, name, value) = of(name == :unescaped ? value(node) : value)

  def value(node)
    forced = FORCED.find { |flag, _| node.public_send(flag) }
    forced ? node.unescaped.dup.force_encoding(forced.last) : node.unescaped
  end

  def string(node)
    return [:string, value(node)] if node.type == :string_node
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

  def piece(part) = part.type == :string_node ? [:string, value(part)] : of(part)

  def joined(pieces)
    runs = pieces.chunk_while { |left, right| text?(left) && text?(right) }
    runs.map { |run| text?(run.first) ? [:string, run.sum("") { |piece| piece[1] }] : run.first }
  end

  def text?(piece) = piece.first == :string
end
