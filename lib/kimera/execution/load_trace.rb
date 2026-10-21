# frozen_string_literal: true

require "prism"
require_relative "../registry/mutation_point"
require_relative "../support/syntax"
require_relative "macro_lambdas"

module Kimera
  module Execution
  end
end

# Watches the suite load: which in-scope files it loads, and which of their
# methods and blocks run while it does. Warm coverage starts after loading,
# so code that ran only then (a class-body macro, a lambda a class body calls
# to build a constant) is judged in the isolated tier, never called uncovered.
class Kimera::Execution::LoadTrace
  LOADED = Kimera::MutationPoint::LOAD_REASON
  BOOTED = Kimera::MutationPoint::BOOT_REASON
  RAN = { call: [Prism::DefNode], b_call: [Prism::BlockNode, Prism::LambdaNode] }.freeze

  Span =
    Data.define(:range, :holes) do
      def holds?(point) = point.inside?([range]) && !point.inside?(holes)
    end

  def initialize(registry, root)
    @registry = registry
    @root = root
  end

  def record(&)
    files = sources
    TracePoint.new(:call, :b_call, :class) { |trace| hit(files[trace.path], trace) }.enable(&).tap { required(files) }
  end

  def loaded?(file) = touched.include?(file)

  def quarantine!(coverage)
    runs.each do |file, lines|
      loaded(file, lines).each { |point| point.uncovered?(coverage) ? point.unsafe!(LOADED) : point.revisit!(BOOTED) }
    end
    Kimera::Execution::MacroLambdas.new(@registry, root).quarantine!(coverage)
  end

  private

  def runs = @_runs ||= Hash.new { |found, file| found[file] = Set.new }

  def touched = @_touched ||= Set.new

  def root = @_root ||= File.expand_path(@root)

  def sources
    @registry.files.each_with_object({}) do |file, found|
      path = File.join(root, file)
      [path, *(File.realpath(path) if File.exist?(path))].each { |known| found[known] = file }
    end
  end

  def hit(file, trace)
    return unless file
    touched << file
    runs[file] << [trace.event, trace.lineno]
  end

  def required(files) = touched.merge($LOADED_FEATURES.filter_map { |feature| files[feature] })

  def loaded(file, lines)
    spans = spans(Kimera::Syntax.parse(File.read(File.join(root, file), encoding: Encoding::UTF_8)).value, lines)
    @registry.at(file).select { |point| point.safe? && spans.any? { |span| span.holds?(point) } }
  end

  def spans(node, lines)
    own = started?(node, lines) ? [Span.new(node.location, holes(node))] : []
    own + node.compact_child_nodes.flat_map { |child| spans(child, lines) }
  end

  def started?(node, lines)
    line = node.location.start_line
    RAN.any? { |event, kinds| kinds.any? { |kind| node.is_a?(kind) } && lines.include?([event, line]) }
  end

  def holes(node) = node.is_a?(Prism::DefNode) ? [] : defined_within(node)

  def defined_within(node)
    node.compact_child_nodes.flat_map { |child| child.is_a?(Prism::DefNode) ? [child.location] : defined_within(child) }
  end
end
