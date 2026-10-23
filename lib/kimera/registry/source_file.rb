# frozen_string_literal: true

require "prism"
require_relative "default_removal"
require_relative "memo_guard"
require_relative "memoization"
require_relative "../rewrite/outcomes"
require_relative "mutation_point"
require_relative "walking"

class Kimera::RegistryScan::SourceFile
  include Kimera::RegistryWalking

  DIRECTIVE = ->((_key, variant)) { variant.directive }

  def initialize(source, file:, operators:, numbering:)
    @source = source
    @file = file
    @operators = operators
    @numbering = numbering
  end

  def points = scanned.first

  def regions = scanned.last

  private

  def tainted = @_tainted ||= Kimera::Memoization.new(@source).ranges + removals.ranges

  def guards = @_guards ||= Kimera::MemoGuard::Source.new(@source).exemptions + removals.exemptions

  def removals = @_removals ||= Kimera::DefaultRemoval::Source.new(@source)

  def scanned = @_scanned ||= scan(Kimera::Syntax.parse(@source))

  def scan(parsed)
    return [[], [unparsed(parsed.errors.first&.message)]] if parsed.failure?
    root = parsed.value
    operators = @operators.map { |operator| operator.survey(root) }
    self.class.new(@source, file: @file, operators: operators, numbering: @numbering).mined(root)
  end

  def unparsed(error)
    Kimera::Unmutated.new(@file, 1, [@source.lines.size, 1].max, "#{Kimera::Unmutated::UNPARSED}#{error}")
  end

  def region(block)
    Kimera::Unmutated.new(@file, *Kimera::Location.parse(block.location).range.minmax, Kimera::Unmutated::BLOCK)
  end

  protected

  def mined(root)
    found = []
    held = {}.compare_by_identity
    walk(root, origin) do |node, cursor|
      point = bank(node, cursor)
      point ? found << point : held.update(hold(node, cursor))
    end
    [found, held.values]
  end

  private

  def origin
    Kimera::RegistryWalking::Cursor.new(
      position: nil, inside_def: nil, in_pattern: nil, def_body: nil, defname: nil, embedded: nil, block: nil
    )
  end

  def bank(node, cursor)
    pairs = harvest(applicable(cursor), node, cursor.position).reject { |key, _| guarded?(node, key) }
    pairs = writable(node, pairs)
    return if pairs.empty?
    classed(assemble(node, pairs, cursor.defname), cursor, pairs).taint!(tainted)
  end

  def hold(node, cursor)
    block = cursor.block
    return {} unless block && !cursor.inside_def && harvest(skipped, node, cursor.position).any?
    { block => region(block) }
  end

  def skipped = @operators.reject(&:body?).reject(&:statement?)

  def applicable(cursor)
    chosen = cursor.inside_def ? @operators : @operators.select(&:body?)
    cursor.position ? chosen : chosen.reject(&:statement?)
  end

  def guarded?(node, key) = guards.any? { |guard| guard.location == node.location && guard.operator == key }

  def harvest(operators, node, position)
    operators.flat_map { |operator| operator.pairs(node, position: position) }
  end

  def assemble(node, pairs, name) = Kimera::MutationPoint.new(**attributes(node, distinct(node, pairs), name))

  def classed(point, cursor, pairs)
    point.unsafe!(Kimera::MutationPoint::CLASS_BODY_REASON) unless cursor.inside_def || toggled?(pairs)
    point
  end

  def toggled?(pairs) = pairs.all? { |key, _| @operators.any? { it.toggles? && it.key == key } }

  def writable(node, pairs) = outcomes.writable(node, pairs, &DIRECTIVE)

  def distinct(node, pairs) = outcomes.distinct(node, pairs, &DIRECTIVE)

  def outcomes = @_outcomes ||= Kimera::Rewrite::Outcomes.new(@source)

  def attributes(node, pairs, name)
    location = node.location
    { point_id: @numbering.point, file: @file, operator: pairs.map(&:first).uniq.join("+") }
      .merge(node_type: node.type.to_s, location: Kimera::Location.parse(location), original_source: location.slice)
      .merge(method_name: name, mutants: mint(pairs))
  end

  def mint(pairs)
    pairs.map { |(_key, variant)| Kimera::Mutant.of(@numbering.mutant, variant) }
  end
end
