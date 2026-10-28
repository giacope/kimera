# frozen_string_literal: true

require_relative "../scribe"
require_relative "../rewrite/directive"
require_relative "../rewrite/numbered_params"
require_relative "guardrail_dispatch"
require_relative "guard_clause"
require_relative "guard_probe"
require_relative "guard_site"
require_relative "guard_text"
require_relative "splice_index"

class Kimera::GuardSplice
  NUMBERED = /\b#{Kimera::Rewrite::NumberedParams::PREFIX}(?:[1-9]|it)\b/

  def initialize(map, points)
    @map = map
    @points = points
  end

  def edits
    sites = guards
    outer = sites.select { |site| site.outer?(sites) }
    outer.map { |site| site.edit(sites, probes) } + probes.reject { |probe| outer.any? { |site| site.holds?(probe) } }
  end

  def applied = @points.zip(placements).select(&:last).flat_map { |point, _| point.ids }

  def rest = @points.zip(placements).reject(&:last).map(&:first)

  private

  def placed = placements.compact

  def guards
    placed.flat_map(&:first).group_by(&:first).map { |node, found| Kimera::GuardText.of(node, found.map { it.drop(1) }) }
  end

  def probes = placed.flat_map(&:last)

  def placements = @_placements ||= @points.map { |point| placement(point, index.node(point)) }

  def placement(point, node)
    return unless node
    hidden, shown = point.mutants.partition { |mutant| mutant.directive[Kimera::Rewrite::TYPE] == "privatize" }
    clauses, sited = clauses(node, shown)
    guards = sited.map { |mutant, _| guarded(node, mutant) }
    [guards, probed(node, hidden) + clauses.flat_map(&:last)] if guards.all?
  end

  def clauses(node, mutants)
    mutants.map { |mutant| [mutant, Kimera::GuardClause.new(node, mutant).edits] }.partition(&:last)
  end

  def probed(node, hidden) = hidden.empty? ? [] : Kimera::GuardProbe.new(node, hidden.map(&:id)).edits

  def guarded(node, mutant)
    kind = Kimera::GuardrailDispatch::PARAMETERS[node.type]
    return [node.value, mutant.id, %(raise(ArgumentError, "missing #{kind}: #{node.name}"))] if kind
    site, mutated = sites.of(node, Kimera::Rewrite::Directive.new(mutant.directive).apply(node))
    text = written(site, mutated)
    [site, mutant.id, text] if fits?(text)
  rescue StandardError
    nil
  end

  def written(site, mutated) = Kimera::Scribe.new(mutated).at(@map.ast, site).after(site).unbroken.text

  def fits?(text) = !text.match?(NUMBERED) && !text.include?("\n")

  def index = @_index ||= Kimera::SpliceIndex.new(@map.ast)

  def sites = @_sites ||= Kimera::GuardSite.new(index)
end
