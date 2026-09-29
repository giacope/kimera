# frozen_string_literal: true

require_relative "../operators/base"

require_relative "../support/unparse"

require_relative "../error"
require_relative "../registry/registry"
require_relative "guard_weaver"
require_relative "source_map"
require_relative "superclass_pin"

class Kimera::Overlay
  Result =
    Struct.new(:file, :source, :mutant_ids, :skipped_unsafe, keyword_init: true) do
      def install(path)
        Kimera::Overlay.evaluate(source, path)
        mutant_ids
      end

      def settle!(points, detail)
        skipped_unsafe.concat(points.flat_map { |point| point.orphan!(mutant_ids, detail) })
      end
    end

  def initialize(registry)
    @registry = registry
  end

  class << self
    def evaluate(source, path)
      Kimera::Warnings.silence { TOPLEVEL_BINDING.eval(Kimera::SuperclassPin.pin(source), path) }
    end
  end

  def synthesize(file, source)
    safe, unsafe = @registry.at(file).partition(&:safe?)
    return unsafe(file, source, unsafe) if safe.empty?
    Kimera::Overlay::FileWeave.new(file, Kimera::SourceMap.new(source), safe, unsafe).result
  end

  def bake(_file, source, id)
    pair = @registry.point(id)
    return source unless pair
    mutant, point = pair
    map = Kimera::SourceMap.new(source)
    map.restore(Kimera::Unparse.unparse(Kimera::Guardrail.new(map, []).bake(point.location, mutant.directive)))
  end

  private

  def unsafe(file, source, points)
    Result.new(file: file, source: source, mutant_ids: [], skipped_unsafe: points.flat_map(&:ids))
  end
end

require_relative "file_weave"
