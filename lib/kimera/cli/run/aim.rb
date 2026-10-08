# frozen_string_literal: true

require_relative "../../error"
require_relative "../../scope/file_set"

class Kimera::CLI::Run::Aim
  def initialize(registry, options)
    @registry = registry
    @options = options
  end

  def restrict(ids)
    return ids if lines.empty? && methods.empty?
    kept = @registry.index.filter_map { |id, point| id if hit?(point) }
    raise(Kimera::UsageError, miss) if kept.empty?
    ids & kept
  end

  private

  def hit?(point) = line?(point) && method?(point)

  def lines = @_lines ||= Hash(@options[:lines]).transform_keys { |path| Kimera::FileSet.relative(path, root) }

  def root = File.expand_path(@options.fetch(:source_root))

  def methods = Array(@options[:methods])

  def line?(point)
    wanted = lines[point.file]
    !wanted || point.location.range.any? { |line| wanted.include?(line) }
  end

  def method?(point) = methods.empty? || methods.include?(point.method_name)

  def miss
    aimed = lines.map { |file, wanted| "#{file}:#{wanted.minmax.uniq.join("-")}" }
    aimed << "method #{methods.join(" or ")}" unless methods.empty?
    "no mutants match #{aimed.join(" and ")} (#{hints.join("; ")})"
  end

  def hints
    found = lines.keys.map { |file| "mutated lines in #{file}: #{listed(starts(file))}" }
    methods.empty? ? found : found << "methods with mutants: #{listed(named)}"
  end

  def starts(file) = @registry.at(file).map { |point| point.location.start_line }.uniq.sort

  def named = @registry.points.filter_map(&:method_name).uniq.sort

  def listed(values) = values.empty? ? "none" : values.join(", ")
end
