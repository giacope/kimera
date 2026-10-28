# frozen_string_literal: true

require_relative "splice_reopening"
require_relative "unwoven"

module Kimera
  module OverlaySplice
    private

    def splice = prepare.map { |prepared| report(*prepared) }

    def prepare
      return [] unless ready?
      edits, dropped = gather
      return [] if edits.empty?
      source = @map.splice(edits + reopenings)
      unwoven?(source, rewritten(edits)) ? [[edits, dropped, source]] : []
    end

    def rewritten(edits) = definitions(@map.ast).select { |node| edits.any? { |edit| edit.first(2) == span(node) } }

    def unwoven?(source, owners)
      result = Kimera::Syntax.parse(source)
      result.success? && Kimera::Unwoven.new(result.value).keeps?(owners)
    end

    def gather
      claims = claimed
      rewritten = claims.map { |definition, mine| [rewrite(definition, mine), mine] }
      kept, lost = rewritten.partition { |edits, _| edits.any? }
      [kept.flat_map(&:first), lost.flat_map(&:last) + (@safe - claims.flat_map(&:last))]
    end

    def reopenings = Kimera::SpliceReopening.new(@map).edits

    def report(edits, dropped, source)
      applied = edits.flat_map(&:last)
      announce(applied, dropped)
      dropped.each { |point| point.unmutatable!("kimera could not write its method") }
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
        "kimera: #{@file}: could not write the whole file; " \
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
      from, to = span(definition)
      @safe.select { |point| !claimed.include?(point) && point.location.inside?(from, to) }
    end

    def definitions(root)
      nodes = []
      Kimera::Rewrite::AstWalk.new(root).visit { |node| nodes << node if node.type == :def_node }
      nodes
    end

    def span(node) = [node.location.start_offset, node.location.end_offset]

    def rewrite(definition, points)
      texts, applied = Kimera::Guardrail.new(@map, points).rewrite(definition)
      texts.map { |text| span(definition) + [text, applied] }
    rescue StandardError
      []
    end
  end
end
