# frozen_string_literal: true

require_relative "../scribe"
require_relative "../rewrite/ast_walk"
require_relative "../rewrite/numbered_params"
require_relative "splice_diff"
require_relative "splice_reopening"

# One baked mutant written into its original source: the rewritten node's
# text replaces the node's span, so comments, magic comments, `__END__` and
# its data, and every line outside the span stay as they were. A shorter
# rewrite is padded inside parentheses to the span's lines. Each attempt must
# read back as the whole mutated tree, or the next one out is tried: the
# smallest node the rewrite changed, then each node around it.
class Kimera::BakeSplice
  Attempt =
    Data.define(:from, :to, :text, :grouping) do
      def self.plain(from, to, text) = new(from, to, text, nil)

      def self.grouped(from, to, text) = new(from, to, text, from + text.bytesize)

      def grouped?(node)
        location = node.location
        node.type == :parentheses_node && location.start_offset == from && location.end_offset == grouping
      end
    end

  # Where a bake may be written, smallest first: the nodes inside the point's
  # that the rewrite changed, the point's own, then each node around it up to
  # the program's statements.
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
    texts = [scribe.joined, scribe].map(&:text).uniq
    texts.lazy.flat_map { |text| attempts(node, text) }.filter_map { |attempt| read(attempt) }.first
  rescue StandardError
    nil
  end

  def attempts(node, text)
    from = node.location.start_offset
    to = node.location.end_offset
    short = node.slice.count("\n") - text.count("\n")
    padded = Attempt.grouped(from, to, "(#{text}#{"\n" * short})") if short.positive?
    [padded, Attempt.plain(from, to, text), Attempt.grouped(from, to, "(#{text})")].compact
  end

  def read(attempt)
    spliced = @map.splice([[attempt.from, attempt.to, attempt.text]])
    result = Kimera::Syntax.parse(spliced)
    spliced if result.success? && written(ungrouped(result.value, attempt)) == @expected
  end

  def written(tree) = Kimera::Scribe.new(Kimera::Rewrite::NumberedParams.new(tree).normalize).source

  def ungrouped(tree, attempt)
    Kimera::Rewrite::AstWalk.new(tree).rebuild do |rebuilt, original|
      attempt.grouped?(original) ? rebuilt.body.body.first : rebuilt
    end
  end

  def reopened(spliced)
    map = Kimera::SourceMap.new(spliced)
    map.splice(Kimera::SpliceReopening.new(map).edits)
  end
end
