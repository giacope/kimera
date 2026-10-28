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
  def initialize(map, points, index: Kimera::SpliceIndex.new(map.ast), sites: Kimera::GuardSite.new(index))
    @map = map
    @points = points
    @index = index
    @sites = sites
  end

  def edits
    sites = guards
    outer = sites.select { |site| site.outer?(sites) }
    outer.map { |site| site.edit(sites, probes) } + probes.reject { |probe| outer.any? { |site| site.holds?(probe) } }
  end

  def applied = @points.zip(placements).reject { |_, found| found.empty? }.flat_map { |point, _| point.ids }

  def rest = @points.zip(placements).select { |_, found| found.empty? }.map(&:first)

  private

  def placed = placements.flatten(1)

  def guards
    placed.flat_map(&:first).group_by(&:first).map { |node, found| Kimera::GuardText.of(node, found.map { it.drop(1) }) }
  end

  def probes = placed.flat_map(&:last)

  def placements = @_placements ||= @points.map { |point| @index.anchored(point).flat_map { placement(point, it) } }

  def placement(point, node)
    hidden, shown = point.mutants.partition { |mutant| Kimera::Rewrite::Directive.new(mutant.directive).kind?("privatize") }
    clauses, sited = clauses(node, shown)
    guards = sited.map { |mutant, _| guarded(node, mutant) }
    guards.all?(&:any?) ? [[guards.flatten(1), probed(node, hidden) + clauses.flat_map(&:last)]] : []
  end

  def clauses(node, mutants)
    mutants.map { |mutant| [mutant, Kimera::GuardClause.new(node, mutant).edits] }.partition(&:last)
  end

  def probed(node, hidden) = hidden.empty? ? [] : Kimera::GuardProbe.new(node, hidden.map(&:id)).edits

  def guarded(node, mutant)
    parameter = Kimera::GuardrailDispatch::Parameter.new(node)
    return [[node.value, mutant.id, parameter.missing]] if parameter.optional?
    site, mutated = @sites.of(node, Kimera::Rewrite::Directive.new(mutant.directive).apply(node))
    text = written(site, mutated)
    fits?(text) ? [[site, mutant.id, text]] : []
  rescue StandardError
    []
  end

  def written(site, mutated) = Kimera::Scribe.new(mutated).at(@map.ast, site).after(site).unbroken.text

  def fits?(text) = !Kimera::Rewrite::NumberedParams::Spelling.new(text).renamed? && !text.include?("\n")
end
