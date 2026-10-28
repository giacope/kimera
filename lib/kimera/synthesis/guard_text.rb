# frozen_string_literal: true

require_relative "guard_span"

Kimera::GuardText =
  Data.define(:node, :entries) do
    def from = span.from

    def to = span.to

    def span = Kimera::GuardSpan.of(node)

    def inside?(other) = !equal?(other) && other.from <= from && to <= other.to

    def outer?(sites) = sites.none? { |other| inside?(other) }

    def holds?(edit) = from < edit.first && edit[1] < to

    def text(sites, probes)
      inner = sites.select { |other| other.inside?(self) }
      children = inner.select { |child| child.outer?(inner) }
      edits = children.map { |child| child.edit(inner, probes, from) } + own(children, probes)
      guarded(written(edits))
    end

    def written(edits) = span.text(Kimera::SourceMap.new(span.slice).splice(edits))

    def own(children, probes)
      mine = probes.select { |probe| holds?(probe) && children.none? { |child| child.holds?(probe) } }
      mine.map { |start, finish, text| [start - from, finish - from, text] }
    end

    def edit(sites, probes, base = 0) = [from - base, to - base, text(sites, probes)]

    def guarded(original)
      tests = entries.map { |id, _| "::Kimera::RUNTIME.active?(#{Integer(id)})" }
      "(!(#{tests.join(" || ")}) ? (#{original}) : #{chained(tests, entries.map(&:last))})"
    end

    def chained(tests, written)
      pairs = tests[0...-1].zip(written).reverse
      pairs.reduce("(#{written.last})") { |rest, (test, each)| "#{test} ? (#{each}) : #{rest}" }
    end
  end
