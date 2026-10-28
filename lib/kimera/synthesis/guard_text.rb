# frozen_string_literal: true

Kimera::GuardText =
  Data.define(:node, :entries) do
    def from = node.location.start_offset

    def to = node.location.end_offset

    def inside?(other) = !equal?(other) && other.from <= from && to <= other.to

    def outer?(sites) = sites.none? { |other| inside?(other) }

    def holds?(edit) = from < edit.first && edit[1] < to

    def text(sites, probes)
      inner = sites.select { |other| other.inside?(self) }
      children = inner.select { |child| child.outer?(inner) }
      edits = children.map { |child| child.edit(inner, probes, from) } + own(children, probes)
      guarded(Kimera::SourceMap.new(node.slice).splice(edits))
    end

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
