# frozen_string_literal: true

require_relative "../scribe"
require_relative "../rewrite/ast_walk"
require_relative "../rewrite/numbered_params"
require_relative "clause_cut"
require_relative "part_splice"
require_relative "readback"
require_relative "line_pad"
require_relative "splice_diff"
require_relative "splice_reopening"

class Kimera::BakeSplice
  INTERPOLATED = %i[interpolated_string_node interpolated_x_string_node].freeze
  WORDS = %i[string_node symbol_node].freeze
  WORD = /\A\w+[?!=]?\z/

  def initialize(map, changed, expected)
    @map = map
    @changed = changed
    @expected = expected
  end

  def source
    candidates = Candidates.new(@changed).to_a.lazy
    candidates.flat_map { |node, rebuilt| placed(node, rebuilt) { [] } }.first(1).map { |spliced| reopened(spliced) }
  end

  private

  def placed(node, rebuilt)
    ways = [-> { cut(node, rebuilt) }, -> { lined(node, rebuilt) }, -> { worded(node, rebuilt) }]
    [*ways, -> { laid(node, rebuilt) }].lazy.flat_map(&:call).first(1)
  rescue StandardError
    yield
  end

  def cut(node, rebuilt)
    attempts = Kimera::ClauseCut.new(@map, node, rebuilt).attempts
    attempts.lazy.flat_map { |head, rest| read(Attempt.new(*head), rest) }.first(1)
  end

  def worded(node, rebuilt)
    return [] unless WORDS.include?(node.type) && rebuilt.type == node.type && !node.opening_loc && !node.closing_loc
    value = rebuilt.unescaped
    location = node.location
    value.match?(WORD) ? read(Attempt.plain(location.start_offset, location.end_offset, value), []) : []
  end

  def lined(node, rebuilt)
    literal = literals.find { |each| holds?(each, node) }
    edit = literal && rebuilt.respond_to?(:unescaped) && Kimera::PartSplice.new(literal).edit(node, rebuilt)
    edit ? read(Attempt.plain(*edit), []) : []
  end

  def laid(node, rebuilt)
    scribe = Kimera::Scribe.new(rebuilt).over(@map.ast, node)
    texts = [scribe, scribe.joined].map(&:text).uniq
    cleared = cleared(node, rebuilt)
    texts.lazy.flat_map { |text| attempts(node, text) }.flat_map { |attempt| read(attempt, cleared) }.first(1)
  end

  def cleared(node, rebuilt)
    kept = Set.new.compare_by_identity.merge(Kimera::Rewrite::AstWalk.new(rebuilt).nodes)
    trailing(node).reject { |doc| kept.include?(doc) }.map { |doc| blank(doc) }
  end

  def trailing(node) = heredocs.select { |doc| trailing?(doc, node.location) }

  def trailing?(doc, location)
    opening = doc.location
    inside = opening.start_offset.between?(location.start_offset, location.end_offset - 1)
    inside && opening.start_line == location.end_line
  end

  def blank(doc)
    start = Kimera::PartSplice.new(doc).body.start_offset
    finish = doc.closing_loc.end_offset
    [start, finish, "\n" * @map.slice(start, finish).count("\n")]
  end

  def heredocs = @_heredocs ||= literals.select(&:heredoc?)

  def literals
    @_literals ||=
      [].tap do |found|
        Kimera::Rewrite::AstWalk.new(@map.ast).visit { |node| found << node if literal?(node) }
      end
  end

  def holds?(literal, node)
    literal.respond_to?(:parts) && literal.parts.any? { it.equal?(node) }
  end

  def literal?(node) = INTERPOLATED.include?(node.type) || (node.respond_to?(:heredoc?) && node.heredoc?)

  def attempts(node, text)
    from = node.location.start_offset
    to = node.location.end_offset
    *laid, grouped = Kimera::LinePad.new(node.slice).layouts(text)
    return [] unless grouped
    [*laid.map { |each| Attempt.plain(from, to, each) }, Attempt.grouped(from, to, grouped)]
  end

  def read(attempt, cleared)
    spliced = @map.splice([attempt.edit, *cleared])
    result = Kimera::Syntax.parse(spliced)
    result.success? && written(ungrouped(result.value, attempt)) == @expected ? [spliced] : []
  end

  def written(tree) = Kimera::Readback.new(tree).text

  def ungrouped(tree, attempt)
    Kimera::Rewrite::AstWalk.new(tree).rebuild do |rebuilt, original|
      attempt.grouped?(original) ? lone(rebuilt.body) : rebuilt
    end
  end

  def lone(body) = body.type == :statements_node && body.body.one? ? body.body.fetch(0) : body

  def reopened(spliced)
    map = Kimera::SourceMap.new(spliced)
    map.splice(Kimera::SpliceReopening.new(map).edits)
  end
end

require_relative "bake_splice/attempt"

require_relative "bake_splice/candidates"
