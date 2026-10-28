# frozen_string_literal: true

module Kimera
end

class Kimera::Unescaped
  FORCED = { forced_utf8_encoding?: Encoding::UTF_8, forced_binary_encoding?: Encoding::BINARY }.freeze

  def initialize(node)
    @node = node
  end

  def text
    value = @node.unescaped
    forced = FORCED.find { |flag, _| @node.public_send(flag) }&.last
    forced ? value.dup.force_encoding(forced) : value
  end
end
