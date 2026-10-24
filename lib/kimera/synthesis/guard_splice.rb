# frozen_string_literal: true

require_relative "../scribe"
require_relative "../rewrite/directive"
require_relative "../rewrite/numbered_params"
require_relative "guardrail_dispatch"
require_relative "guard_probe"
require_relative "guard_site"
require_relative "guard_text"
require_relative "splice_index"

# Warm schemata written into the original source. Each mutant is guarded at
# the smallest expression its rewrite changes (Kimera::GuardText), its
# alternative written on one line (a kept text that breaks a line written
# afresh), so every line keeps its number. A point no expression can hold (a
# rescue clause, a definition that is not a statement, an alternative Scribe
# cannot write on one line) is left in `rest`, for the caller to write its
# definition whole.
class Kimera::GuardSplice
  NUMBERED = /\b#{Kimera::Rewrite::NumberedParams::PREFIX}(?:[1-9]|it)\b/

  def initialize(map, points)
    @map = map
    @points = points
  end

  def edits
    sites = placed.flat_map(&:first).group_by(&:first).map { |node, found| Kimera::GuardText.new(node, found.map { it.drop(1) }) }
    sites.select { |site| site.outer?(sites) }.map { |site| site.edit(sites) } + placed.flat_map(&:last)
  end

  def applied = @points.zip(placements).select(&:last).flat_map { |point, _| point.ids }

  def rest = @points.zip(placements).reject(&:last).map(&:first)

  private

  def placed = placements.compact

  def placements = @_placements ||= @points.map { |point| placement(point, index.node(point)) }

  def placement(point, node)
    hidden, shown = point.mutants.partition { |mutant| mutant.directive[Kimera::Rewrite::TYPE] == "privatize" }
    guards = shown.map { |mutant| guarded(node, mutant) }
    probes = hidden.empty? ? [] : probed(node, hidden)
    [guards, probes] if node && guards.all? && probes
  end

  def probed(node, hidden)
    Kimera::GuardProbe.new(node, hidden.map(&:id)).edits if node
  end

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
