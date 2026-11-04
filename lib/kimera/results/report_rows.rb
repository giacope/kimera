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
      mutant, point = @registry[id] { return base }
      base.merge("key" => @keys[id]).merge(rewritten(id, mutant, point.to_h))
    end

    private

    def rewritten(id, mutant, row)
      place(row, mutant).merge(rendered(id, mutant, row))
    end

    def rendered(id, mutant, row)
      texts = @registry.texts(id, Kimera::Rewrite::MutantText)
      { "original" => row["original_source"], "mutated" => texts.map { |text| parenthesised(mutant, text) }.first }
    end

    def parenthesised(mutant, mutated)
      mutant.rewrite(Kimera::Rewrite::Directive).kind?("boolean_connective") ? "(#{mutated})" : mutated
    end

    def place(row, mutant)
      Kimera::Location.from_h(row["location"]).position
        .merge("method" => row["method_name"], "operator" => row["operator"], "label" => mutant.to_s)
    end
  end
end
