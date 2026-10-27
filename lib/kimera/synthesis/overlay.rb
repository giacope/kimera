# frozen_string_literal: true

require_relative "../operators/base"

require_relative "../scribe"

require_relative "../error"
require_relative "../registry/registry"
require_relative "guard_weaver"
require_relative "point_lines"
require_relative "source_map"
require_relative "superclass_pin"

class Kimera::Overlay
  Result =
    Struct.new(:file, :source, :mutant_ids, :skipped_unsafe, keyword_init: true) do
      def install(path)
        Kimera::Overlay::Source.new(source).evaluate(path)
        mutant_ids
      end

      def settle!(points, detail)
        skipped_unsafe.concat(points.flat_map { |point| point.orphan!(mutant_ids, detail) })
      end
    end

  class Unbakeable < Kimera::Error; end

  UNWRITTEN = "kimera could not write it"

  def initialize(registry)
    @registry = registry
  end

  def synthesize(file, source)
    safe, unsafe = @registry.at(file).partition(&:safe?)
    return unsafe(file, source, unsafe) if safe.empty?
    Kimera::Overlay::FileWeave.new(file, Kimera::SourceMap.new(source), safe, unsafe).result
  end

  def bake(_file, source, id)
    pair = @registry.point(id)
    return source unless pair
    map = Kimera::SourceMap.new(source)
    checked(map, pair.last, spliced(map, *pair) || write(map, baked(map, *pair), pair.last))
  end

  private

  def spliced(map, mutant, point)
    changed = Kimera::Guardrail.new(map, []).changes(point, mutant.directive)
    expected, original = changed && expectation(changed.last&.last || map.ast, map.ast)
    return unless expected
    raise(Unbakeable, "#{UNWRITTEN} (the mutant reads as the original)") if expected == original
    Kimera::BakeSplice.new(map, changed, expected).source
  end

  def expectation(*trees)
    trees.map { |tree| Kimera::Scribe.new(tree).source }
  rescue StandardError
    nil
  end

  def checked(map, point, text)
    raise(Unbakeable, "#{UNWRITTEN} (what it wrote does not parse)") unless Kimera::Syntax.parse(text).success?
    return text if Kimera::PointLines.new(map, point.location).kept?(text)
    raise(Unbakeable, "#{UNWRITTEN} (what it wrote changes or moves a line outside the mutation)")
  end

  def baked(map, mutant, point)
    Kimera::Guardrail.new(map, []).bake(point, mutant.directive) ||
      raise(Unbakeable, Kimera::Overlay::FileWeave::UNMATCHED)
  end

  def write(map, tree, point)
    map.restore(Kimera::Scribe.new(tree).source)
  rescue StandardError => error
    Kimera::Overlay::MethodBake.new(map, tree).source(point.location) ||
      raise(Unbakeable, "kimera could not write its bake (#{error.class}: #{error.message})")
  end

  def unsafe(file, source, points)
    Result.new(file: file, source: source, mutant_ids: [], skipped_unsafe: points.flat_map(&:ids))
  end
end

require_relative "file_weave"
require_relative "bake_splice"
require_relative "method_bake"
require_relative "overlay/source"
