# frozen_string_literal: true

require_relative "../support/unparse"
require_relative "overlay_splice"

class Kimera::Overlay::FileWeave
  include Kimera::OverlaySplice

  UNGUARDABLE = "unparser could not round-trip its guard"
  UNMATCHED = "no node to guard: the parser folds it into its parent (as in `--1`)"

  def initialize(file, map, safe, unsafe)
    @file = file
    @map = map
    @safe = safe
    @unsafe = unsafe
  end

  def result
    (attempt(@safe) || fallback).tap { |result| result.settle!(@safe, UNMATCHED) }
  end

  private

  def io = @_io ||= $stderr

  def attempt(points)
    render(Kimera::Guardrail.new(@map, points))
  rescue StandardError
    nil
  end

  def render(weaver)
    Kimera::Overlay::Result.new(
      file: @file, source: @map.restore(Kimera::Unparse.unparse(weaver.tree)), mutant_ids: weaver.applied,
      skipped_unsafe: @unsafe.flat_map(&:ids)
    )
  end

  def fallback
    viable = bisect(@safe)
    return recover if viable.empty?
    finish(viable)
  end

  def finish(viable)
    dropped = @safe - viable
    notice(dropped)
    dropped.each { |point| point.unmutatable!(UNGUARDABLE) }
    attempt(viable).tap { |result| result.skipped_unsafe.concat(dropped.flat_map(&:ids)) }
  end

  def notice(dropped)
    io.puts(
      "kimera: #{@file}: #{dropped.size} mutation point(s) at " \
        "#{dropped.map { |p| "line #{p.location.start_line}" }.uniq.join(", ")} " \
        "are unguardable (unparser round-trip); their mutants are reported unmutatable"
    )
  end

  def recover
    spliced = splice
    return spliced if spliced
    @map.restore(Kimera::Unparse.unparse(Kimera::Guardrail.new(@map, @safe).tree))
  end

  def bisect(points)
    return points if attempt(points)
    count = points.size
    return [] if count <= 1
    merge(points, count)
  end

  def merge(points, count)
    half = count / 2
    merged = bisect(points[0...half]) + bisect(points[half..])
    merged.pop while merged.any? && !attempt(merged)
    merged
  end
end
