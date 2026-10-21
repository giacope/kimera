# frozen_string_literal: true

require_relative "../rewrite/directive"
require_relative "test_quality"

module Kimera
  module ReportRows
    def quality = notes.suite&.then { |suite| Kimera::TestQuality.new(@results, suite).to_h }

    private

    def flakes
      { "test_quality" => quality, "flaky_tests" => notes.flaky }.compact
    end

    def detailed(result)
      base = result.to_h
      id = result.mutant_id
      pair = @registry&.point(id)
      pair ? base.merge("key" => @registry.keys[id]).merge(rewritten(pair)) : base
    end

    def rewritten(pair)
      mutant, point = pair
      place(point, mutant).merge(rendered(point.original_source, mutant))
    end

    def rendered(original, mutant)
      mutated = Kimera::Rewrite::Directive.new(mutant.directive).render(original)
      { "original" => original, "mutated" => parenthesised(mutant, mutated) }
    end

    def parenthesised(mutant, mutated) = mutant.directive["type"] == "boolean_connective" ? "(#{mutated})" : mutated

    def place(point, mutant)
      point.location.position
        .merge("method" => point.method_name, "operator" => point.operator, "label" => mutant.label)
    end
  end
end
