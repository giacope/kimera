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
    kept = @registry.each.filter_map { |mutant, point, file| mutant.to_i if hit?(point, file) }
    raise(Kimera::UsageError, miss) if kept.empty?
    ids & kept
  end

  private

  def hit?(point, file) = line?(point, file) && method?(point)

  def lines
    @_lines ||= Hash(@options[:lines]).transform_keys { |path| Kimera::FileSet::Root.new(root).relative(path) }
  end

  def root = File.expand_path(@options.to_h.fetch(:source_root))

  def methods = Array(@options[:methods])

  def line?(point, file)
    wanted = lines[file]
    !wanted || point.fits?(lines: wanted)
  end

  def method?(point) = methods.empty? || point.fits?(methods: methods)

  def miss
    aimed = lines.map { |file, wanted| "#{file}:#{wanted.minmax.uniq.join("-")}" }
    aimed << "method #{methods.join(" or ")}" unless methods.empty?
    "no mutants match #{aimed.join(" and ")} (#{hints.join("; ")})"
  end

  def hints
    found =
      lines.keys.map do |file|
        "mutated lines in #{file}: #{listed(@registry.to_h.fetch(file, [])) { it.dig("location", "start_line") }}"
      end
    methods.empty? ? found : found << "methods with mutants: #{listed(@registry.to_a) { it["method_name"] }}"
  end

  def listed(points)
    values = points.filter_map { |point| yield(point.to_h) }
    values.empty? ? "none" : values.uniq.sort.join(", ")
  end
end
