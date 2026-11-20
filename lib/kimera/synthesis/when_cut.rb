# frozen_string_literal: true

class Kimera::WhenCut
  def initialize(map, node)
    @map = map
    @node = node
  end

  def edits
    return [] unless @node.type == :case_node
    clauses = @node.conditions
    clauses.each_with_index.map { |clause, index| blank(clause.location.start_offset, following(clauses[index + 1])) }
  end

  private

  def following(clause)
    (clause&.location || @node.else_clause&.else_keyword_loc || @node.end_keyword_loc).start_offset
  end

  def blank(from, to)
    text = @map.slice(from, to)
    [from, to, "#{"\n" * text.count("\n")}#{text[/[ \t]*\z/]}"]
  end
end
