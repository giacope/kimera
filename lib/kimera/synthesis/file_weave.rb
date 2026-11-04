# frozen_string_literal: true

require_relative "../scribe"
require_relative "method_splice"
require_relative "overlay_stitch"

class Kimera::Overlay
  class FileWeave
    UNGUARDABLE = "kimera could not write its guard"

    def initialize(file, map, safe, unsafe)
      @file = file
      @map = map
      @safe = safe
      @unsafe = unsafe
    end

    def result(io = $stderr)
      attempt(@safe).fetch(0) { fallback(io) }.tap { |result| result.settle!(@safe, UNMATCHED) }
    end

    private

    def attempt(points) = Kimera::Overlay::Stitch.new(@file, @map, points, @unsafe).results

    def fallback(io)
      viable = bisect(@safe)
      return recover(io) if viable.empty?
      finish(viable, io)
    end

    def finish(viable, io)
      dropped = @safe - viable
      notice(dropped, io)
      dropped.each { |point| point.unmutatable!(UNGUARDABLE) }
      attempt(viable).fetch(0).tap { |result| result.skip!(dropped) }
    end

    def notice(dropped, io)
      io.puts(
        "kimera: #{@file}: #{dropped.size} mutation point(s) at " \
          "#{dropped.map { |p| "line #{p.location.start_line}" }.uniq.join(", ")} " \
          "are unguardable (kimera could not write them); their mutants are reported unmutatable"
      )
    end

    def recover(io)
      spliced = Kimera::Overlay::MethodSplice.new(@file, @map, @safe, @unsafe).results(io)
      spliced.fetch(0) { raise(Kimera::Scribe::Unreadable, UNGUARDABLE) }
    end

    def bisect(points)
      return points if attempt(points).any?
      count = points.size
      return [] if count <= 1
      merge(points, count)
    end

    def merge(points, count)
      half = count / 2
      merged = bisect(points[0...half]) + bisect(points[half..])
      merged.pop while merged.any? && attempt(merged).empty?
      merged
    end
  end
end
