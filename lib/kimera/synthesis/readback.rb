# frozen_string_literal: true

require_relative "../scribe"
require_relative "../rewrite/numbered_params"

class Kimera::Readback
  def initialize(tree)
    @tree = tree
  end

  def faithful?(text)
    result = Kimera::Syntax.parse(text)
    result.success? && written(read(result.value)) == meant
  end

  private

  def read(program) = @tree.type == :program_node ? program : lone(program.statements)

  def lone(statements) = statements.body.one? ? statements.body.first : statements

  def meant = @_meant ||= written(@tree)

  def written(tree) = Kimera::Scribe.new(Kimera::Rewrite::NumberedParams.new(tree).normalize).source
end
