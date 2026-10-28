# frozen_string_literal: true

require_relative "../scribe"
require_relative "../rewrite/numbered_params"

class Kimera::Readback
  def initialize(tree)
    @tree = tree
  end

  def faithful?(source)
    result = Kimera::Syntax.parse(source)
    result.success? && written(lone(result.value.statements)) == text
  end

  def text = @_text ||= written(@tree)

  private

  def lone(statements) = statements.body.one? ? statements.body.first : statements

  def written(tree) = Kimera::Scribe.new(Kimera::Rewrite::NumberedParams.new(tree).normalize).source
end
