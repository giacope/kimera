# frozen_string_literal: true

require_relative "rails_declaration"

class Kimera::Operators::RailsAssociation < Kimera::Operators::RailsDeclaration
  NAMES = %i[has_many has_one belongs_to has_and_belongs_to_many].freeze

  class << self
    def key = "rails_association"
  end

  private

  def declaration(node)
    return unless dependent?(node)
    solo("#{first(node)}: drop dependent:", "kwarg_pair_drop", key: "dependent")
  end

  def dependent?(node)
    keywords(node)&.elements.to_a.any? do |assoc|
      assoc.is_a?(AssocNode) && unescaped(assoc.key) == "dependent"
    end
  end
end
