# frozen_string_literal: true

require_relative "guard_span"

class Kimera::GuardText
  def initialize(span, entries)
    @span = span
    @entries = entries
  end

  def self.of(node, entries) = new(Kimera::GuardSpan.of(node), entries)

  def outer?(sites) = sites.none? { |other| inside?(other) }

  def holds?(edit) = from < edit.first && edit[1] < to

  def edit(sites, probes, base = 0) = [from - base, to - base, text(sites, probes)]

  protected

  def from = @span.from

  def to = @span.to

  def inside?(other) = !equal?(other) && other.from <= from && to <= other.to

  private

  def text(sites, probes)
    inner = sites.select { |other| other.inside?(self) }
    children = inner.select { |child| child.outer?(inner) }
    edits = children.map { |child| child.edit(inner, probes, from) } + own(children, probes)
    guarded(@span.text(Kimera::SourceMap.new(@span.slice).splice(edits)))
  end

  def own(children, probes)
    mine = probes.select { |probe| holds?(probe) && children.none? { |child| child.holds?(probe) } }
    mine.map { |start, finish, text| [start - from, finish - from, text] }
  end

  def guarded(original)
    tests = @entries.map { |id, _| "::Kimera::RUNTIME.active?(#{Integer(id)})" }
    written = @entries.map(&:last)
    chain =
      tests[0...-1].zip(written).reverse.reduce("(#{written.last})") do |rest, (test, each)|
        "#{test} ? (#{each}) : #{rest}"
      end
    "(!(#{tests.join(" || ")}) ? (#{original}) : #{chain})"
  end
end
