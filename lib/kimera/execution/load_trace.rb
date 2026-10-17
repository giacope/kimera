# frozen_string_literal: true

require "prism"
require_relative "../registry/mutation_point"
require_relative "../support/syntax"

module Kimera
  module Execution
  end
end

class Kimera::Execution::LoadTrace
  LOADED = Kimera::MutationPoint::LOAD_REASON
  BOOTED = Kimera::MutationPoint::BOOT_REASON

  def initialize(registry, root)
    @registry = registry
    @root = root
  end

  def record(&)
    files = sources
    TracePoint.new(:call) { |trace| hit(files[trace.path], trace.lineno) }.enable(&)
  end

  def quarantine!(coverage)
    calls.each do |file, lines|
      loaded(file, lines).each { |point| uncovered?(point, coverage) ? point.unsafe!(LOADED) : point.revisit!(BOOTED) }
    end
  end

  private

  def calls = @_calls ||= Hash.new { |found, file| found[file] = Set.new }

  def root = @_root ||= File.expand_path(@root)

  def sources
    @registry.files.each_with_object({}) do |file, found|
      path = File.join(root, file)
      [path, *(File.realpath(path) if File.exist?(path))].each { |known| found[known] = file }
    end
  end

  def hit(file, line)
    calls[file] << line if file
  end

  def loaded(file, lines)
    ranges = defs(Kimera::Syntax.parse(File.read(File.join(root, file), encoding: Encoding::UTF_8)).value, lines)
    @registry.at(file).select { |point| point.safe? && inside?(point, ranges) }
  end

  def uncovered?(point, coverage) = point.ids.all? { |id| coverage.fetch(id) { coverage.fetch(id.to_s, []) }.empty? }

  def inside?(point, ranges) = ranges.any? { |range| point.location.within?(range.start_offset, range.end_offset) }

  def defs(node, lines)
    location = node.location
    (node.is_a?(Prism::DefNode) && lines.include?(location.start_line) ? [location] : []) +
      node.compact_child_nodes.flat_map { |child| defs(child, lines) }
  end
end
