# frozen_string_literal: true

require_relative "../rewrite/mutant_text"

module Kimera
  class ReportRows
    def initialize(registry, keys = Kimera::MutantKeys.of(registry))
      @registry = registry
      @keys = keys
    end

    def of(result)
      base = result.to_h
      id = base["mutant_id"]
      pair = @registry[id] { return base }
      base.merge("key" => @keys[id]).merge(rewritten(pair))
    end

    private

    def rewritten(pair)
      mutant, point = pair
      place(point, mutant).merge(rendered(point, mutant))
    end

    def rendered(point, mutant)
      texts = @registry.texts(point, mutant, Kimera::Rewrite::MutantText)
      { "original" => point.original_source, "mutated" => texts.map { |text| parenthesised(mutant, text) }.first }
    end

    def parenthesised(mutant, mutated)
      mutant.rewrite(Kimera::Rewrite::Directive).kind?("boolean_connective") ? "(#{mutated})" : mutated
    end

    def place(point, mutant)
      point.location.position.merge("method" => point.method_name, "operator" => point.operator, "label" => mutant.to_s)
    end
  end
end
