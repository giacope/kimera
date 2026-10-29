# frozen_string_literal: true

require_relative "overlay_splice"
require_relative "splice_reopening"
require_relative "unwoven"

class Kimera::Overlay::MethodSplice
  include Kimera::OverlaySplice

  def initialize(file, map, safe, unsafe)
    @file = file
    @map = map
    @safe = safe
    @unsafe = unsafe
  end

  def results(io) = prepare.map { |edits, dropped, source| report(io, edits, dropped, source) }

  def rewrite(definition, points)
    texts, applied = Kimera::Guardrail.new(@map, points).rewrite(definition)
    texts.map { |text| span(definition) + [text, applied] }
  rescue StandardError
    yield
  end

  def woven(applied, source, owners) = unwoven?(source, owners) ? [built(applied, [], source)] : []

  private

  def built(applied, dropped, source)
    Kimera::Overlay::Result.new(
      file: @file, source: source, mutant_ids: applied,
      skipped_unsafe: (@unsafe + dropped).flat_map(&:ids)
    )
  end

  def unwoven?(source, owners)
    result = Kimera::Syntax.parse(source)
    result.success? && Kimera::Unwoven.new(result.value).keeps?(owners)
  end

  def prepare
    writable { return [] }
    edits, dropped = gather
    return [] if edits.empty?
    source = @map.splice(edits + Kimera::SpliceReopening.new(@map).edits)
    unwoven?(source, rewritten(edits)) ? [[edits, dropped, source]] : []
  end

  def rewritten(edits) = definitions(@map.ast).select { |node| edits.any? { |edit| edit.first(2) == span(node) } }

  def gather
    claims = claimed
    rewritten = claims.map { |definition, mine| [rewrite(definition, mine) { [] }, mine] }
    kept, lost = rewritten.partition { |edits, _| edits.any? }
    [kept.flat_map(&:first), lost.flat_map(&:last) + (@safe - claims.flat_map(&:last))]
  end

  def report(io, edits, dropped, source)
    applied = edits.flat_map(&:last)
    announce(io, applied, dropped)
    dropped.each { |point| point.unmutatable!("kimera could not write its method") }
    built(applied, dropped, source)
  end

  def announce(io, applied, dropped)
    io.puts(
      "kimera: #{@file}: could not write the whole file; " \
        "#{applied.size} mutant(s) spliced per method, " \
        "#{dropped.flat_map(&:ids).size} reported unmutatable"
    )
  end

  def writable
    Kimera::Guardrail.new(@map, []).tree
  rescue StandardError
    yield
  end

  def claimed
    definitions(@map.ast).reduce([]) do |claims, definition|
      mine = points(definition, claims.flat_map(&:last))
      mine.empty? ? claims : [*claims, [definition, mine]]
    end
  end

  def points(definition, claimed)
    from, to = span(definition)
    @safe.select { |point| !claimed.include?(point) && point.location.inside?(from, to) }
  end
end
