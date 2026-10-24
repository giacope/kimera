# frozen_string_literal: true

require_relative "rails_declaration"

# Deletes a validation, and drops each option of a `validates` call that
# keeps a validator without it (`length:` alone, beside `presence:`), so a
# changed constraint is judged on its own, not only by the whole call.
class Kimera::Operators::RailsValidation < Kimera::Operators::RailsDeclaration
  NAMES = %i[validates validate validates_with validates_each].freeze
  # Rails' own validates options; every other key names a validator.
  SHARED = %w[if unless on allow_blank allow_nil strict].freeze

  def key = "rails_validation"

  private

  def narrowed(node)
    keys = node.name == :validates ? named(node) : []
    validators = keys - SHARED
    dropped = keys - (validators.one? ? validators : [])
    dropped.map { |key| mutation("validates: drop #{key}:", "kwarg_pair_drop", key:) }
  end

  def named(node) = keywords(node)&.elements.to_a.filter_map { |assoc| unescaped(assoc.key) if assoc.is_a?(AssocNode) }
end
