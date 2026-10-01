# frozen_string_literal: true

require "prism"
require_relative "../registry/mutation_point"
require_relative "../support/syntax"

module Kimera
  module Execution
  end
end

class Kimera::Execution::LoadTrace
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
      loaded(file, lines).each { |point| point.unsafe!(Kimera::MutationPoint::LOAD_REASON) if uncovered?(point, coverage) }
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

  def defs(node, lines, found = [])
    location = node.location
    found << location if node.is_a?(Prism::DefNode) && lines.include?(location.start_line)
    node.compact_child_nodes.each { |child| defs(child, lines, found) }
    found
  end
end
