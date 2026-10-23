# frozen_string_literal: true

# The guard spliced where one expression stood: the original slice first,
# with the guards of the expressions inside it, then each mutant's
# alternative, tested in order.
#   (!(::Kimera::RUNTIME.active?(1) || ::Kimera::RUNTIME.active?(2)) ? (a > b)
#     : ::Kimera::RUNTIME.active?(1) ? (a >= b) : (a < b))
Kimera::GuardText =
  Data.define(:node, :entries) do
    def from = node.location.start_offset

    def to = node.location.end_offset

    def inside?(other) = !equal?(other) && other.from <= from && to <= other.to

    def outer?(sites) = sites.none? { |other| inside?(other) }

    def text(sites)
      inner = sites.select { |other| other.inside?(self) }
      edits = inner.select { |child| child.outer?(inner) }.map { |child| child.edit(inner, from) }
      guarded(Kimera::SourceMap.new(node.slice).splice(edits))
    end

    def edit(sites, base = 0) = [from - base, to - base, text(sites)]

    def guarded(original)
      tests = entries.map { |id, _| "::Kimera::RUNTIME.active?(#{Integer(id)})" }
      "(!(#{tests.join(" || ")}) ? (#{original}) : #{chained(tests, entries.map(&:last))})"
    end

    def chained(tests, written)
      pairs = tests[0...-1].zip(written).reverse
      pairs.reduce("(#{written.last})") { |rest, (test, each)| "#{test} ? (#{each}) : #{rest}" }
    end
  end
