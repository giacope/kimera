# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::KeywordDrop < Kimera::Operators::Base
  def key = "keyword_drop"

  def variants(node, **)
    return unless identifier?(node)
    keywords(node)&.elements.to_a.filter_map { |assoc| drop(assoc) }
  end

  private

  def drop(assoc)
    name = assoc.is_a?(AssocNode) && unescaped(assoc.key)
    return unless name
    mutation("drop keyword `#{name}:`", "kwarg_pair_drop", key: name)
  end
end
