# frozen_string_literal: true

require_relative "../support/syntax_types"
require_relative "vocabulary"

class Kimera::Operators::Base
  SYNTAX = ->(node) { Kimera::Syntax.view(node) }
  include Kimera::SyntaxTypes
  include Kimera::Operators::Vocabulary

  def key = raise(NotImplementedError, "#{self.class} must define #key")

  def statement? = false

  def body? = false

  def variants(node, position:)
    raise(NotImplementedError, "#{self} must define #variants")
  end

  def pairs(node, position:)
    Array(variants(node, position: position)).map { |variant| [key, variant] }
  end

  def syntax(node) = self.class::SYNTAX.call(node)
end
