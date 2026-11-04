# frozen_string_literal: true

require_relative "../rewrite/mutant_text"

module Kimera
  class ReportRows
    def initialize(registry)
      @registry = registry
    end

    def of(result)
      base = result.to_h
      id = base["mutant_id"]
      pair = @registry.point(id) { return base }
      base.merge("key" => @registry.keys[id]).merge(rewritten(pair))
    end

    private

    def rewritten(pair)
      mutant, point = pair
      place(point, mutant).merge(rendered(point, mutant))
    end

    def rendered(point, mutant)
      texts = Kimera::Rewrite::MutantText.new(point, mutant, root: @registry.root).texts
      { "original" => point.original_source, "mutated" => texts.map { |text| parenthesised(mutant, text) }.first }
    end

    def parenthesised(mutant, mutated) = mutant.directive["type"] == "boolean_connective" ? "(#{mutated})" : mutated

    def place(point, mutant)
      point.location.position
        .merge("method" => point.method_name, "operator" => point.operator, "label" => mutant.label)
    end
  end
end
