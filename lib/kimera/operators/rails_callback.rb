# frozen_string_literal: true

require_relative "rails_declaration"

class Kimera::Operators::RailsCallback < Kimera::Operators::RailsDeclaration
  NAMES = %i[
    before_action after_action around_action
    before_save after_save before_create after_create
    before_update after_update before_destroy after_destroy
    before_validation after_validation after_commit after_rollback
    after_initialize after_find after_touch
  ].freeze

  class << self
    def key = "rails_callback"
  end

  private

  def declaration(node)
    deletion(node) + scopes(node)
  end

  def scopes(node)
    keywords(node)&.elements.to_a.flat_map { |assoc| scope(node, assoc) }
  end

  def scope(node, assoc)
    return [] unless scopable?(assoc)
    indexed(node, unescaped(assoc.key), assoc.value.elements)
  end

  def scopable?(assoc)
    return false unless assoc.is_a?(AssocNode)
    return false unless %w[only except].include?(unescaped(assoc.key))
    assoc.value.is_a?(ArrayNode)
  end

  def indexed(node, key, elements)
    elements.each_index.map { |index| variant(node, key, elements, index) }
  end

  def variant(node, key, elements, index)
    Kimera::Operators::Variant.new(
      label: "#{node.name}: drop #{elements[index].location.slice} from #{key}:",
      directive: directive("kwarg_element_drop", key: key, index: index)
    )
  end
end
