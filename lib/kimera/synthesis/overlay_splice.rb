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
      claims = claimed
      rewritten = claims.map { |definition, mine| [rewrite(definition, mine), mine] }
      [rewritten.filter_map(&:first), rewritten.reject(&:first).flat_map(&:last) + (@safe - claims.flat_map(&:last))]
    end

    def reopenings = Kimera::SpliceReopening.new(@map).edits

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

    def claimed
      definitions(@map.ast).reduce([]) do |claims, definition|
        mine = points(definition, claims.flat_map(&:last))
        mine.empty? ? claims : [*claims, [definition, mine]]
      end
    end

    def points(definition, claimed)
      from, to = @map.span(definition.location.expression)
      @safe.select { |point| !claimed.include?(point) && point.location.inside?(from, to) }
    end

    def definitions(root)
      nodes = []
      Kimera::Rewrite::AstWalk.new(root).visit { |node| nodes << node if %i[def defs].include?(node.type) }
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
