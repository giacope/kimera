# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::StatementDeletion < Kimera::Operators::Base
  DIAGNOSTIC_NAMES = %i[puts print pp p].freeze
  LOGGER = %i[logger @logger].freeze

  class << self
    def key = Kimera::Operators::STATEMENT_DELETION

    def statement? = true
  end

  def variants(node, **)
    return unless identifier?(node)
    return if diagnostic?(node)
    deletion(node)
  end

  private

  def diagnostic?(node)
    syntax(node).diagnostic?(DIAGNOSTIC_NAMES, LOGGER)
  end
end
