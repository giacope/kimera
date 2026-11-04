# frozen_string_literal: true

module Kimera
  class IgnoreList
    class Match
      def initialize(point, mutant)
        @point = point
        @mutant = mutant
      end

      def rule?(rule)
        given = rule.slice(*ANCHORS).select { |_field, value| value }
        label = given.delete(:label)
        (!label || label == mutant.to_s) && point.fits?(**given)
      end
      private

      attr_reader :point, :mutant
    end

    class Resolution
      def initialize(ids:, stale:, moved:)
        @ids = ids
        @stale = stale
        @moved = moved
      end

      def ignored(eligible) = @ids & eligible

      def alert(listener)
        @stale.each { |rule| listener.stale(rule) }
        @moved.each { |shift| listener.moved(shift) }
      end

      def to_h = { ids: @ids, stale: @stale, moved: @moved.map(&:to_s) }
    end

    class Shift
      def initialize(rule, line)
        @rule = rule
        @line = line
      end

      def to_s = "#{rule[:file]}:#{rule[:line]} → #{line} [#{rule[:label]}]"

      private

      attr_reader :rule, :line
    end

    ANCHORS = %i[line column label method original starts operator].freeze

    def initialize(rules)
      @rules = rules
    end

    def resolve(registry)
      placements = placed(registry)
      kept = uncontested(placements)
      Resolution.new(
        ids: kept.flat_map(&:ids).uniq.sort, stale: lapsed(placements, kept),
        moved: kept.flat_map(&:moved)
      )
    end

    private

    def placed(registry)
      candidates = Hash.new { |cache, glob| cache[glob] = pairs(registry, glob) }
      Array(@rules).map { |rule| Placement.new(rule, candidates[rule[:file]]) }
    end

    def uncontested(placements)
      claimed = placements.flat_map(&:ids).tally.select { |_id, count| count > 1 }.keys
      placements.reject { |placement| placement.contested?(claimed) }
    end

    def lapsed(placements, kept)
      placements.flat_map { |placement| placement.lapsed(kept) }
    end

    def pairs(registry, glob)
      matched = registry.to_h.select { |file, _| glob && File.fnmatch?(glob, file, File::FNM_PATHNAME) }
      matched.values.flatten(1).flat_map { |point| point.each.map { |mutant| [mutant, point] } }
    end
  end
end

require_relative "ignore_placement"
