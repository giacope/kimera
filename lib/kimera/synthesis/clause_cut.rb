# frozen_string_literal: true

require_relative "../parsing/syntax"

class Kimera::ClauseCut
  BODIES = %i[begin_node statements_node].freeze

  def initialize(source, node, rebuilt)
    @source = source
    @node = node
    @rebuilt = rebuilt
  end

  def attempts
    return [] unless @node.type == :begin_node && BODIES.include?(@rebuilt.type)
    variants.map { |edits| [[*edits.first, grouping(edits)], edits.drop(1)] }
  end

  private

  def variants
    clauses = [*rescues, *otherwise, *ensured]
    opening = @node.begin_keyword_loc
    return [clauses] unless opening && !kept
    [%w[; ;], %w[( )]].map { |open, close| [word(opening, open), *clauses, word(@node.end_keyword_loc, close)] }
  end

  def grouping(edits) = @node.location.end_offset + edits.sum { |from, to, text| text.bytesize - (to - from) }

  def kept = @rebuilt.type == :begin_node ? @rebuilt : nil

  def clauses = Kimera::Syntax::RESCUES.call(@node.rescue_clause)

  def rescues
    left = Kimera::Syntax::RESCUES.call(kept&.rescue_clause).map { |clause| clause.location.start_offset }
    clauses.each_with_index.filter_map do |clause, index|
      blank(clause.keyword_loc.start_offset, following(index)) unless left.include?(clause.location.start_offset)
    end
  end

  def following(index)
    after = clauses[index + 1]&.keyword_loc || @node.else_clause&.else_keyword_loc
    (after || @node.ensure_clause&.ensure_keyword_loc || @node.end_keyword_loc).start_offset
  end

  def otherwise
    keyword = @node.else_clause&.else_keyword_loc
    keyword && !kept&.else_clause ? [word(keyword, ";")] : []
  end

  def ensured
    keyword = @node.ensure_clause&.ensure_keyword_loc
    keyword && !kept&.ensure_clause ? [blank(keyword.start_offset, @node.end_keyword_loc.start_offset)] : []
  end

  def word(keyword, text) = [keyword.start_offset, keyword.end_offset, text]

  def blank(from, to)
    text = @source.byteslice(from, to - from)
    [from, to, ";#{"\n" * text.count("\n")}#{text[/[ \t]*\z/]}"]
  end
end
