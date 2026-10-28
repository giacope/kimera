# frozen_string_literal: true

require_relative "../parsing/syntax"
require_relative "../rewrite/directive"

class Kimera::GuardClause
  DROPS = %w[drop_rescue drop_ensure].freeze

  def initialize(node, mutant)
    @node = node
    @mutant = mutant
  end

  def edits
    return unless DROPS.include?(type) && @node&.type == :begin_node
    type == DROPS.first ? rescued : ensured
  end

  private

  def type = @mutant.directive[Kimera::Rewrite::TYPE]

  def test = "::Kimera::RUNTIME.active?(#{Integer(@mutant.id)})"

  def rescued
    clause = Kimera::Syntax::RESCUES.call(@node.rescue_clause)[Integer(@mutant.directive[Kimera::Rewrite::INDEX])]
    clause && caught(clause.exceptions.map(&:location), clause.keyword_loc.end_offset)
  end

  def caught(listed, after)
    return [insert(after, " *(#{test} ? [] : ::StandardError)")] if listed.empty?
    [insert(listed.first.start_offset, "*(#{test} ? [] : ["), insert(listed.last.end_offset, "])")]
  end

  def ensured
    clause = @node.ensure_clause
    body = clause&.statements
    body && [insert(clause.ensure_keyword_loc.end_offset, "; if !(#{test})"), insert(body.location.end_offset, "; end")]
  end

  def insert(at, text) = [at, at, text]
end
