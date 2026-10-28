# frozen_string_literal: true

require_relative "../property_helper"
require_relative "../../support/tree_shape"
require "kimera/scribe"
require "kimera/synthesis/source_map"

# Every tree Scribe writes reads back as that tree: kimera's own sources, its
# example apps and evaluation fixtures, and unparser's round-trip corpus
# (spec/property/corpus/unparser, MIT, from unparser 083f55d), the forms its
# authors collected because a writer gets them wrong. Each file is parsed,
# written whole by Scribe with its magic comments kept, parsed again and
# compared as TreeShape, a string by the value and encoding Ruby gives it, a
# lone expression in parentheses being that expression. A file Prism cannot
# read is no tree to write; a tree Scribe refuses (Scribe::Unbound) is written
# by no bake. R6B4-M1..M3: `when 90.. then "A"` read as `when 90.."A"`, `in
# %w[a b]` as an array pattern, `"\u{3042}"` in a binary file as binary.
RSpec.describe(Kimera::Scribe) do
  def self.root = File.expand_path("../../..", __dir__)

  def self.files = Dir[File.join(root, "{lib,examples,eval/fixtures,spec/property/corpus}/**/*.rb")]

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

  def shape(tree) = TreeShape.of(bare(tree))

  def misread(source)
    tree = Prism.parse(source)
    tree.success? ? reread(Kimera::SourceMap.new(source).restore(described_class.new(tree.value).source), tree) : nil
  rescue described_class::Unbound
    nil
  end

  def reread(written, tree)
    back = Prism.parse(written)
    return "does not parse: #{back.errors.first.message}" unless back.success?
    "reads back as another tree" unless shape(back.value) == shape(tree.value)
  end

  def relative(path) = path.delete_prefix("#{self.class.root}/")

  def wrong(path)
    problem = misread(File.read(path, encoding: Encoding::UTF_8))
    "#{relative(path)}: #{problem}" if problem
  end

  it "reads its corpus" do
    expect(self.class.files.map { |path| relative(path) }).to(include(end_with("corpus/unparser/literal/flipflop.rb")))
  end

  files.each_slice(40).with_index do |slice, index|
    it "writes every tree of slice #{index + 1} so it reads back as that tree" do
      expect(slice.filter_map { |path| wrong(path) }).to(be_empty)
    end
  end
end
