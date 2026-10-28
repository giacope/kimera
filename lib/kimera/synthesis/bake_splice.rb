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
    spliced = candidates.filter_map { |node, rebuilt| placed(node, rebuilt) }.first
    spliced && reopened(spliced)
  end

  private

  def placed(node, rebuilt)
    cut(node, rebuilt) || lined(node, rebuilt) || worded(node, rebuilt) || laid(node, rebuilt)
  rescue StandardError
    nil
  end

  def cut(node, rebuilt)
    attempts = Kimera::ClauseCut.new(@map.source, node, rebuilt).attempts
    attempts.lazy.filter_map { |head, rest| read(Attempt.new(*head), rest) }.first
  end

  def worded(node, rebuilt)
    return unless WORDS.include?(node.type) && rebuilt.type == node.type && !node.opening_loc && !node.closing_loc
    value = rebuilt.unescaped
    location = node.location
    read(Attempt.plain(location.start_offset, location.end_offset, value), []) if value.match?(WORD)
  end

  def lined(node, rebuilt)
    literal = literals.find { |each| holds?(each, node) }
    edit = literal && rebuilt.respond_to?(:unescaped) && Kimera::PartSplice.new(literal).edit(node, rebuilt)
    edit && read(Attempt.plain(*edit), [])
  end

  def laid(node, rebuilt)
    scribe = Kimera::Scribe.new(rebuilt).over(@map.ast, node)
    texts = [scribe, scribe.joined].map(&:text).uniq
    cleared = cleared(node, rebuilt)
    texts.lazy.flat_map { |text| attempts(node, text) }.filter_map { |attempt| read(attempt, cleared) }.first
  end

  def cleared(node, rebuilt)
    kept = Set.new.compare_by_identity
    Kimera::Rewrite::AstWalk.new(rebuilt).visit { |each| kept << each }
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
    [start, finish, "\n" * @map.source.byteslice(start, finish - start).count("\n")]
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
    pad = Kimera::LinePad.new(node.slice)
    laid = pad.texts(text).map { |each| Attempt.plain(from, to, each) }
    laid.empty? ? laid : [*laid, Attempt.grouped(from, to, "(#{pad.padded(text)})")]
  end

  def read(attempt, cleared)
    spliced = @map.splice([[attempt.from, attempt.to, attempt.text], *cleared])
    result = Kimera::Syntax.parse(spliced)
    spliced if result.success? && written(ungrouped(result.value, attempt)) == @expected
  end

  def written(tree) = Kimera::Readback.new(tree).text

  def ungrouped(tree, attempt)
    Kimera::Rewrite::AstWalk.new(tree).rebuild do |rebuilt, original|
      attempt.grouped?(original) ? lone(rebuilt.body) : rebuilt
    end
  end

  def lone(body) = body.type == :statements_node && body.body.one? ? body.body.first : body

  def reopened(spliced)
    map = Kimera::SourceMap.new(spliced)
    map.splice(Kimera::SpliceReopening.new(map).edits)
  end
end

Kimera::BakeSplice::Attempt =
  Data.define(:from, :to, :text, :grouping) do
    def self.plain(from, to, text) = new(from, to, text, nil)

    def self.grouped(from, to, text) = new(from, to, text, from + text.bytesize)

    def grouped?(node)
      location = node.location
      node.type == :parentheses_node && [location.start_offset, location.end_offset] == [from, grouping]
    end
  end

Kimera::BakeSplice::Candidates =
  Data.define(:changed) do
    def to_a = [*Kimera::SpliceDiff.new(*changed.first).path.drop(1).reverse, *changed[0...-1]]
  end
