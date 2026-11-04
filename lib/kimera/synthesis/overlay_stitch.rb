# frozen_string_literal: true

require_relative "guard_splice"
require_relative "method_splice"
require_relative "overlay_splice"
require_relative "splice_reopening"

class Kimera::Overlay::Stitch
  include Kimera::OverlaySplice

  def initialize(file, map, safe, unsafe)
    @file = file
    @map = map
    @safe = safe
    @unsafe = unsafe
  end

  def results
    whole = enclosing(weave.rest)
    rewritten = whole&.map { |held| splicer.rewrite(*held) { [] } }
    rewritten&.all?(&:any?) ? stitched(whole, rewritten.flatten(1)) : []
  end

  private

  def weave(splices = Kimera::GuardSplice) = @_weave ||= splices.new(@map, @safe)

  def splicer = Kimera::Overlay::MethodSplice.new(@file, @map, @safe, @unsafe)

  def stitched(whole, rewritten)
    source = spliced(whole, rewritten)
    return [] unless source
    held = whole.flat_map(&:last).flat_map { |point| point.each.map(&:to_i) }
    applied = weave.applied - held + rewritten.flat_map(&:last)
    splicer.woven(applied, source, whole.map(&:first))
  end

  def spliced(whole, rewritten)
    kept = weave.edits.reject { |edit| whole.any? { |definition, _| covers?(definition, edit) } }
    edits = [*kept, *rewritten.map { |edit| edit.first(3) }, *Kimera::SpliceReopening.new(@map).edits]
    ordered = edits.sort_by { |from, to, _| [from, to] }
    @map.splice(ordered) if disjoint?(ordered) && kept?(ordered)
  end

  def kept?(edits) = edits.all? { |from, to, text| Kimera::LinePad.new(@map.slice(from, to)).kept?(text) }

  def disjoint?(edits) = edits.each_cons(2).all? { |left, right| left[1] <= right.first }

  def enclosing(points)
    holders = [*definitions(@map.ast), *@map.ast.statements.body]
    owners = points.map { |point| holders.find { |holder| holds?(holder, point) } }
    owners.uniq.map { |owner| [owner, @safe.select { |point| holds?(owner, point) }] } if owners.all?
  end

  def holds?(definition, point) = point.fits?(inside: span(definition))

  def covers?(definition, edit) = Range.new(*span(definition)).cover?(edit.first..edit[1])
end
