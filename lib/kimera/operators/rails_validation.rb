# frozen_string_literal: true

require_relative "rails_declaration"

class Kimera::Operators::RailsValidation < Kimera::Operators::RailsDeclaration
  NAMES = %i[validates validate validates_with validates_each].freeze

  def key = "rails_validation"

  private

  def declaration(node)
    deletion(node)
  end
end
