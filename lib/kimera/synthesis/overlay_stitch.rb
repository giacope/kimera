# frozen_string_literal: true

require_relative "guard_splice"
require_relative "overlay_splice"

class Kimera::Overlay::Stitch
  include Kimera::OverlaySplice

  def initialize(file, map, safe, unsafe)
    @file = file
    @map = map
    @safe = safe
    @unsafe = unsafe
  end

  def result
    whole = enclosing(weave.rest)
    rewritten = whole&.map { |definition, mine| rewrite(definition, mine) }
    stitched(whole, rewritten) if rewritten&.all?
  end

  private

  def weave = @_weave ||= Kimera::GuardSplice.new(@map, @safe)

  def stitched(whole, rewritten)
    source = spliced(whole, rewritten)
    applied = weave.applied - whole.flat_map(&:last).flat_map(&:ids) + rewritten.flat_map(&:last)
    build(applied, [], source) if source && Kimera::Syntax.parse(source).success?
  end

  def spliced(whole, rewritten)
    kept = weave.edits.reject { |edit| whole.any? { |definition, _| covers?(definition, edit) } }
    edits = (kept + rewritten.map { |edit| edit.first(3) } + reopenings).sort_by { |from, to, _| [from, to] }
    @map.splice(edits) if disjoint?(edits) && @map.lines_kept?(edits)
  end

  def disjoint?(edits) = edits.each_cons(2).all? { |left, right| left[1] <= right.first }

  def enclosing(points)
    holders = [*definitions(@map.ast), *@map.ast.statements.body]
    owners = points.map { |point| holders.find { |holder| holds?(holder, point.location) } }
    owners.uniq.map { |owner| [owner, @safe.select { |point| holds?(owner, point.location) }] } if owners.all?
  end

  def holds?(definition, location) = location.inside?(*span(definition))

  def covers?(definition, edit) = Range.new(*span(definition)).cover?(edit.first..edit[1])
end
