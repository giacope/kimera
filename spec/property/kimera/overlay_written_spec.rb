# frozen_string_literal: true

require_relative "../property_helper"
require_relative "../../support/tree_shape"
require "kimera/registry/builder"
require "kimera/synthesis/overlay"

# Every mutant kimera writes is the mutant: for each point and operator over
# kimera's own sources and the example apps, the bake parses, differs from the
# original, and reads back as the mutated tree. Both sides are read the way
# kimera reads every file (numbered parameters named), written once by Scribe
# (which spells a sign, a heredoc or a call one way) and compared as
# TreeShape, a lone expression in parentheses being that expression. A
# factory-built constant is reopened on both sides alike. A seeded sample of
# files keeps it fast; `PBT_SCALE` widens it and `PBT_SEED` picks another.
RSpec.describe(Kimera::Overlay) do
  seed = Integer(ENV.fetch("PBT_SEED", "20261023"))
  root = File.expand_path("../../..", __dir__)
  files = Dir[File.join(root, "{lib,examples}/**/*.rb")].reject { |path| path.include?("/vendor/") }.sort

  def read(text) = Kimera::Rewrite::NumberedParams.new(Kimera::Scribe.parse(text)).normalize

  def shape(text) = TreeShape.of(bare(read(Kimera::Scribe.new(read(text)).source)))

  def bare(node)
    return node.map { |item| bare(item) } if node.is_a?(Array)
    return node unless node.is_a?(Prism::Node)
    lone = lone(node)
    lone ? bare(lone) : node.copy(**children(node).transform_values { |value| bare(value) })
  end

  def lone(node)
    body = node.body if node.type == :parentheses_node
    body.body.first if body&.type == :statements_node && body.body.one?
  end

  def children(node) = node.deconstruct_keys(nil).select { |_, value| value.is_a?(Prism::Node) || value.is_a?(Array) }

  def expected(map, mutant, point)
    tree = Kimera::Guardrail.new(map, []).changes(point, mutant.directive).last.last
    written = Kimera::SourceMap.new(Kimera::Scribe.new(tree).source)
    shape(written.splice(Kimera::SpliceReopening.new(written).edits))
  end

  def unlike(path, source)
    catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["all"])).source(source, file: "x.rb")
    overlay = described_class.new(catalog)
    catalog.each.filter_map do |mutant, point|
      problem = written(overlay.bake("x.rb", source, mutant.id), source, mutant, point)
      "#{path}:#{point.location.start_line} #{mutant.label}: #{problem}" if problem
    rescue Kimera::Overlay::Unbakeable
      nil
    end
  end

  def written(baked, source, mutant, point)
    return "does not parse" unless Prism.parse(baked).success?
    return "reads as the original" if baked == source
    "misread" unless shape(baked) == expected(Kimera::SourceMap.new(source), mutant, point)
  end

  files.sample((6 * PropertyRuns::SCALE).ceil, random: Random.new(seed)).each do |path|
    it "writes every mutant of #{path.delete_prefix("#{root}/")} as the mutated tree" do
      expect(unlike(path, File.read(path, encoding: Encoding::UTF_8))).to(be_empty)
    end
  end
end
