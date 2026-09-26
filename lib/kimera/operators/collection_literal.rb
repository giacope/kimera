# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::CollectionLiteral < Kimera::Operators::Base
  EMPTIED = { ArrayNode => "array => []", HashNode => "hash => {}" }.freeze

  class << self
    def key = "collection_literal"
  end

  def variants(node, **)
    case node
    when ArrayNode, HashNode
      solo(EMPTIED[node.class], "empty_collection") unless node.elements.empty?
    end
  end
end
