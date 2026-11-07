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
    return unless DROPS.any? { |drop| directive.kind?(drop) } && @node&.type == :begin_node
    directive.kind?(DROPS.first) ? rescued : ensured
  end

  private

  def directive = @mutant.rewrite(Kimera::Rewrite::Directive)

  def test = "::Kimera::RUNTIME.active?(#{Integer(@mutant)})"

  def rescued
    clause = Kimera::Rescues.new(@node.rescue_clause).to_a[directive.position]
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
