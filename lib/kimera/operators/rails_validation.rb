# frozen_string_literal: true

require_relative "rails_declaration"

class Kimera::Operators::RailsValidation < Kimera::Operators::RailsDeclaration
  NAMES = %i[validates validate validates_with validates_each].freeze
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
