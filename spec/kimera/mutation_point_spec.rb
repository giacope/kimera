# frozen_string_literal: true

require "kimera/registry/mutation_point"

using PointFields

RSpec.describe(Kimera::MutationPoint) do
  def sample
    described_class.new(
      point_id: 1, file: "a.rb", operator: "comparison", node_type: "call_node",
      location: Kimera::Location.new(
        start_offset: 0, span: 3, start_line: 1,
        start_column: 0, end_line: 1, end_column: 3
      ),
      original_source: "a > b",
      method_name: "compare",
      mutants: [Kimera::Mutant.new(id: 2, label: "> => <", directive: { "type" => "comparison" })]
    )
  end

  it "round-trips every field (including nested location and mutants)", :aggregate_failures do
    reloaded = described_class.from_h(sample.to_h)
    expect(reloaded.to_h).to(eq(sample.to_h))
    expect([reloaded.point_id, reloaded.file, reloaded.safe?]).to(eq([1, "a.rb", true]))
    expect(reloaded.location.to_h).to(eq(sample.location.to_h))
    expect(reloaded.mutants.map(&:to_h)).to(eq(sample.mutants.map(&:to_h)))
  end

  def keys
    %w[point_id file operator node_type location original_source method_name schema_safe unsafe_reason mutants]
  end

  it "serializes each field under its own key", :aggregate_failures do
    h = sample.to_h
    expect(h.keys).to(match_array(keys))
    expect(h["location"]).to(eq(sample.location.to_h))
    expect(h["mutants"]).to(eq(sample.mutants.map(&:to_h)))
  end

  it "defaults schema_safe to true when the key is absent (older registries)" do
    h = sample.to_h
    h.delete("schema_safe")
    expect(described_class.from_h(h).safe?).to(be(true))
  end

  def unsafe
    point = sample
    point.mark!(Kimera::Reason.class_body)
    point
  end

  it "carries the class-body unsafe reason through the round-trip" do
    reloaded = described_class.from_h(unsafe.to_h)
    reasons = [Kimera::Reason.unsafety, Kimera::Reason.class_body].map { reloaded.reasons(it) }
    expect([reloaded.safe?, *reasons]).to(eq([false, [Kimera::Reason::CLASS_BODY_REASON]] + [[Kimera::Reason::CLASS_BODY_REASON]]))
  end

  describe "#fits?" do
    def fits?(**) = sample.fits?(**)

    it "holds with no criterion, and only when every criterion holds", :aggregate_failures do
      expect(fits?).to(be(true))
      expect(fits?(line: 1, method: "compare")).to(be(true))
      expect(fits?(line: 1, method: "other")).to(be(false))
      expect(fits?(line: 2, method: "compare")).to(be(false))
    end

    it "fails fast on a criterion it does not know" do
      expect { fits?(file: "a.rb") }.to(raise_error(KeyError))
    end

    it "tells whether it is safe", :aggregate_failures do
      expect([fits?(safe: true), fits?(safe: false)]).to(eq([true, false]))
      expect([unsafe.fits?(safe: true), unsafe.fits?(safe: false)]).to(eq([false, true]))
    end

    it "places itself by line, start and column, from numbers or their text", :aggregate_failures do
      expect([fits?(line: 1), fits?(line: "1"), fits?(line: 2)]).to(eq([true, true, false]))
      expect([fits?(starts: 1), fits?(starts: "1"), fits?(starts: 0)]).to(eq([true, true, false]))
      expect([fits?(column: 1), fits?(column: "1"), fits?(column: 0)]).to(eq([true, true, false]))
    end

    it "matches its operator and method by name, one or any of several", :aggregate_failures do
      expect([fits?(operator: "comparison"), fits?(operator: :comparison), fits?(operator: %w[a comparison])])
        .to(eq([true, true, true]))
      expect([fits?(operator: "arithmetic"), fits?(operator: [])]).to(eq([false, false]))
      expect([fits?(method: "compare"), fits?(method: :compare), fits?(method: %w[a compare])])
        .to(eq([true, true, true]))
      expect([fits?(method: "other"), fits?(method: [])]).to(eq([false, false]))
    end

    it "matches its original source whatever the spacing", :aggregate_failures do
      expect([fits?(original: "a  >\n b"), fits?(original: "a > b"), fits?(original: "a > c")])
        .to(eq([true, true, false]))
      expect(fits?(original: :"a > b")).to(be(true))
    end

    it "lies on any of the given lines, or opens within a span of them", :aggregate_failures do
      expect([fits?(lines: [1]), fits?(lines: Set[3, 1]), fits?(lines: [2]), fits?(lines: [])])
        .to(eq([true, true, false, false]))
      expect([fits?(opening: 1..2), fits?(opening: 0..1), fits?(opening: 2..3)]).to(eq([true, true, false]))
    end

    it "lies within given ranges", :aggregate_failures do
      range = Struct.new(:start_offset, :end_offset)
      expect([fits?(within: [range.new(-1, 4)]), fits?(within: [range.new(0, 4)]), fits?(within: [])])
        .to(eq([true, false, false]))
    end

    it "lies inside a span, over an offset, or enters a span", :aggregate_failures do
      expect([fits?(inside: [0, 3]), fits?(inside: [1, 3]), fits?(inside: [0, 2])]).to(eq([true, false, false]))
      expect([fits?(covers: 0), fits?(covers: 2), fits?(covers: 3)]).to(eq([true, true, false]))
      expect([fits?(entered: [0, 1]), fits?(entered: [-1, 0]), fits?(entered: [1, 2])]).to(eq([true, true, false]))
    end

    def node(code) = Kimera::Syntax.parse(code).value.statements.body.first

    it "knows its node: where it starts, of its kind, with its source", :aggregate_failures do
      expect([fits?(node: node("a > b")), fits?(node: node("a > c"))]).to(eq([true, false]))
      expect([fits?(node: node(" a > b")), fits?(node: node("[a > b]"))]).to(eq([false, false]))
      expect(described_class.new(**sample_fields, node_type: "if_node").fits?(node: node("a > b"))).to(be(false))
    end

    it "is kin to a point in the same method", :aggregate_failures do
      expect(fits?(kin: described_class.new(**sample_fields, point_id: 9))).to(be(true))
      expect(fits?(kin: described_class.new(**sample_fields, method_name: "other"))).to(be(false))
      expect(fits?(kin: described_class.none)).to(be(false))
    end
  end

  def sample_fields
    { file: "a.rb", node_type: "call_node", location: sample.location, original_source: "a > b" }
      .merge(method_name: "compare")
  end

  it "finds its node among nodes keyed by where they stand and what they are", :aggregate_failures do
    expect(sample.anchored({ [0, 3, "call_node"] => :found, [0, 3, "if_node"] => :other })).to(be(:found))
    expect(sample.anchored({ [0, 2, "call_node"] => :other }) { :none }).to(be(:none))
    expect { sample.anchored({}) }.to(raise_error(KeyError))
  end

  it "yields its mutants and answers itself, or an enumerator of them", :aggregate_failures do
    point = sample
    seen = []
    expect(point.each { seen << it }).to(be(point))
    expect(seen.map(&:to_i)).to(eq([2]))
    expect(point.each.map(&:to_s)).to(eq(["> => <"]))
  end

  it "prints where it stands, and in which method", :aggregate_failures do
    expect(sample.to_s).to(eq("a.rb:1:1  in compare"))
    expect(described_class.new(**sample_fields, method_name: nil).to_s).to(eq("a.rb:1:1"))
  end
end
