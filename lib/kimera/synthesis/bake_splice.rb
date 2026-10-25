# frozen_string_literal: true

require_relative "../scribe"
require_relative "../rewrite/ast_walk"
require_relative "../rewrite/numbered_params"
require_relative "line_pad"
require_relative "splice_diff"
require_relative "splice_reopening"

class Kimera::BakeSplice
  Attempt =
    Data.define(:from, :to, :text, :grouping) do
      def self.plain(from, to, text) = new(from, to, text, nil)

      def self.grouped(from, to, text) = new(from, to, text, from + text.bytesize)

      def grouped?(node)
        location = node.location
        node.type == :parentheses_node && [location.start_offset, location.end_offset] == [from, grouping]
      end
    end

  Candidates =
    Data.define(:changed) do
      def to_a = [*Kimera::SpliceDiff.new(*changed.first).path.drop(1).reverse, *changed[0...-1]]
    end

  def initialize(map, changed, expected)
    @map = map
    @changed = changed
    @expected = expected
  end

  def source
    spliced = Candidates.new(@changed).to_a.lazy.filter_map { |node, rebuilt| placed(node, rebuilt) }.first
    spliced && reopened(spliced)
  end

  private

  def placed(node, rebuilt)
    scribe = Kimera::Scribe.new(rebuilt).at(@map.ast, node)
    texts = [scribe, scribe.joined].map(&:text).uniq
    texts.lazy.flat_map { |text| attempts(node, text) }.filter_map { |attempt| read(attempt) }.first
  rescue StandardError
    nil
  end

  def attempts(node, text)
    from = node.location.start_offset
    to = node.location.end_offset
    pad = Kimera::LinePad.new(node.slice)
    laid = pad.texts(text).map { |each| Attempt.plain(from, to, each) }
    laid.empty? ? laid : [*laid, Attempt.grouped(from, to, "(#{pad.padded(text)})")]
  end

  def read(attempt)
    spliced = @map.splice([[attempt.from, attempt.to, attempt.text]])
    result = Kimera::Syntax.parse(spliced)
    spliced if result.success? && written(ungrouped(result.value, attempt)) == @expected
  end

  def written(tree) = Kimera::Scribe.new(Kimera::Rewrite::NumberedParams.new(tree).normalize).source

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
