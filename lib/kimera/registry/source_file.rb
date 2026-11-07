# frozen_string_literal: true

require "prism"
require_relative "default_removal"
require_relative "memo_guard"
require_relative "memoization"
require_relative "../rewrite/outcomes"
require_relative "mutation_point"
require_relative "skipped"
require_relative "walking"

class Kimera::RegistryScan::SourceFile
  include Kimera::RegistryWalking

  DIRECTIVE = ->((_key, variant)) { variant.to_h.fetch(:directive) }

  def initialize(source, file:, operators:, numbering:)
    @source = source
    @file = file
    @operators = operators
    @numbering = numbering
  end

  def points = scanned.fetch(0)

  def regions = scanned.fetch(1)

  private

  def tainted = @_tainted ||= Kimera::Memoization.new(@source).ranges + removals.ranges

  def guards = @_guards ||= Kimera::MemoGuard::Source.new(@source).exemptions + removals.exemptions

  def removals(kind = Kimera::DefaultRemoval::Source) = @_removals ||= kind.new(@source)

  def scanned = @_scanned ||= attempt

  def attempt
    scan(Kimera::Syntax.parse(@source))
  rescue StandardError, SystemStackError => error
    [[], [Kimera::Unmutated.whole(@file, last_line, :unscanned, "#{error.class}: #{error.message.lines.first&.chomp}")]]
  end

  def scan(parsed)
    return [[], [Kimera::Unmutated.whole(@file, last_line, :unparsed, parsed.errors.first&.message)]] if parsed.failure?
    root = parsed.value
    operators = @operators.map { |operator| operator.survey(root) }
    self.class.new(@source, file: @file, operators: operators, numbering: @numbering).mined(root)
  end

  def last_line = [@source.lines.size, 1].max

  def unmutated(held)
    held.group_by { |block, _| block.location.start_offset }.values.flat_map { |pairs| runs(pairs.map(&:last)) }
  end

  def runs(nodes)
    Kimera::RegistryScan::Skipped.new(nodes).lines.slice_when { |line, following| following > line + 1 }.map do |run|
      Kimera::Unmutated.block(@file, run.first, run.last)
    end
  end

  protected

  def mined(root)
    found = []
    held = []
    walk(root, origin) do |node, cursor|
      point = bank(node, cursor)
      point ? found << point : held.concat(hold(node, cursor))
    end
    [found, unmutated(held)]
  end

  private

  def origin = Kimera::RegistryWalking::Cursor.origin

  def bank(node, cursor)
    pairs = cursor.pairs(@operators, node).reject { |key, _| guarded?(node, key) }
    pairs = writable(node, pairs)
    return if pairs.empty?
    point = cursor.classed(assemble(node, pairs, cursor), toggled?(pairs))
    point.tap { taints(node).each { |text| point.mark!(Kimera::Reason::Guarded.tainted(text)) } }
  end

  def taints(node)
    location = node.location
    tainted.lazy.flat_map { |range| range.reasons(location.start_offset, location.end_offset) }.first(1)
  end

  def hold(node, cursor) = cursor.held(@operators, node)

  def guarded?(node, key) = guards.any? { |guard| guard.covers?(node, key) }

  def assemble(node, pairs, cursor)
    Kimera::MutationPoint.new(**cursor.named(attributes(node, distinct(node, pairs))))
  end

  def toggled?(pairs) = pairs.all? { |key, _| @operators.any? { it.reach.toggles? && it.key == key } }

  def writable(node, pairs) = outcomes.writable(node, pairs, &DIRECTIVE)

  def distinct(node, pairs) = outcomes.distinct(node, pairs, &DIRECTIVE)

  def outcomes(kind = Kimera::Rewrite::Outcomes) = @_outcomes ||= kind.new(@source)

  def attributes(node, pairs)
    location = node.location
    { point_id: @numbering.point, file: @file, operator: pairs.map(&:first).uniq.join("+") }
      .merge(node_type: node.type.to_s, location: Kimera::Location.parse(location), original_source: location.slice)
      .merge(mutants: mint(pairs))
  end

  def mint(pairs)
    pairs.map { |(_key, variant)| Kimera::Mutant.new(id: @numbering.mutant, **variant.to_h) }
  end
end
