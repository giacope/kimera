# frozen_string_literal: true

require_relative "splice_reopening"

module Kimera
  module OverlaySplice
    private

    def splice
      prepared = prepare
      prepared && report(*prepared)
    end

    def prepare
      return unless ready?
      edits, dropped = gather
      return if edits.empty?
      source = apply(edits + reopenings)
      [edits, dropped, source] if Kimera::Syntax.parse(source).success?
    end

    def gather
      edits = []
      dropped = []
      claimed = each { |definition, points| collect(definition, points, edits, dropped) }
      [edits, dropped + (@safe - claimed)]
    end

    def reopenings = Kimera::SpliceReopening.new(@map).edits

    def collect(definition, points, edits, dropped)
      rewritten = rewrite(definition, points)
      rewritten ? edits << rewritten : dropped.concat(points)
    end

    def report(edits, dropped, source)
      applied = edits.flat_map(&:last)
      announce(applied, dropped)
      dropped.each { |point| point.unmutatable!("unparser could not round-trip its method") }
      build(applied, dropped, source)
    end

    def build(applied, dropped, source)
      Kimera::Overlay::Result.new(
        file: @file, source: source, mutant_ids: applied,
        skipped_unsafe: (@unsafe + dropped).flat_map(&:ids)
      )
    end

    def announce(applied, dropped)
      io.puts(
        "kimera: #{@file}: file-level round-trip failed; " \
          "#{applied.size} mutant(s) spliced per method, " \
          "#{dropped.flat_map(&:ids).size} reported unmutatable"
      )
    end

    def ready?
      Kimera::Guardrail.new(@map, []).tree
      true
    rescue StandardError
      false
    end

    def each(&)
      claimed = []
      definitions.each { |definition| visit(definition, claimed, &) }
      claimed
    end

    def visit(definition, claimed)
      mine = points(definition, claimed)
      return if mine.empty?
      claimed.concat(mine)
      yield(definition, mine)
    end

    def points(definition, claimed)
      from, to = @map.span(definition.location.expression)
      @safe.select { |point| !claimed.include?(point) && point.location.within?(from, to) }
    end

    def definitions
      nodes = []
      Kimera::Rewrite::AstWalk.visit(@map.ast) { |node| nodes << node if %i[def defs].include?(node.type) }
      nodes
    end

    def rewrite(definition, points)
      text, applied = Kimera::Guardrail.new(@map, points).rewrite(definition)
      span(definition) + [text, applied]
    rescue StandardError
      nil
    end

    def span(definition)
      expression = definition.location.expression
      [expression.begin_pos, expression.end_pos]
    end

    def apply(edits)
      edits.sort_by(&:first).reverse_each.with_object(@map.source.dup) do |(from, to, replacement, _ids), text|
        text[from...to] = replacement
      end
    end
  end
end
