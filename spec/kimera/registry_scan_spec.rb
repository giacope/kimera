# frozen_string_literal: true

require "kimera/registry/builder"

RSpec.describe(Kimera::RegistryScan) do
  subject(:registry) { described_class.new.source(source, file: "account.rb") }

  let(:source) do
    <<~RUBY
      class Account
        def overdrawn?(balance, limit)
          balance < limit && active == true
        end

        def settle!(amount)
          ledger.record(amount)
          balance >= 0
        end
      end
    RUBY
  end

  it "detects comparison, boolean connective, literal, and deletion points" do
    operators = registry.points.map(&:operator).uniq
    expect(operators).to(include("comparison", "boolean_connective", "boolean_literal", "statement_deletion"))
  end

  it "captures the original source slice for each point", :aggregate_failures do
    point = registry.points.find { |p| p.original_source == "balance < limit" }
    expect(point).not_to(be_nil)
    expect(point.node_type).to(eq("call_node"))
  end

  it "records each point's enclosing method name", :aggregate_failures do
    point = registry.points.find { |p| p.original_source == "balance < limit" }
    expect(point.method_name).not_to(be_nil)
    expect(registry.points.map(&:method_name).uniq).to(all(be_a(String)))
  end

  it "produces boundary + negation variants for comparison operators" do
    point = registry.points.find { |p| p.original_source == "balance < limit" }
    labels = point.mutants.map(&:label)
    expect(labels).to(contain_exactly("< => <=", "< => >"))
  end

  it "only deletes named call statements, not pure comparisons", :aggregate_failures do
    deletions = registry.points.select { |p| p.operator == "statement_deletion" }
    sources = deletions.map(&:original_source)
    expect(sources).to(include("ledger.record(amount)"))
    expect(sources).not_to(include("balance >= 0"))
  end

  it "labels a statement-deletion mutant with the deleted statement's first line" do
    point = registry.points.find { |p| p.original_source == "ledger.record(amount)" }
    expect(point.mutants.map(&:label)).to(eq(["delete `ledger.record(amount)`"]))
  end

  it "assigns globally unique, deterministic mutant ids", :aggregate_failures do
    ids = registry.each.map { |m, _p| m.id }
    expect(ids).to(eq(ids.uniq))
    expect(ids).to(eq((1..ids.size).to_a))
  end

  it "produces no points for source that fails to parse" do
    # Prism would recover the first def from a partial AST.
    registry = described_class.new.source(
      "def a(x, y)\n  x > y\nend\ndef broken(", file: "bad.rb"
    )
    expect(registry.points).to(eq([]))
  end

  it "marks only the def body's last statement as the implicit-return tail" do
    src = <<~RUBY
      def m(a, b)
        if a
          a + b
        end
        a - b
      end
    RUBY
    builder = described_class.new(operators: Kimera::Operators.build(keys: ["return_value"]))
    registry = builder.source(src, file: "tail.rb")
    tails = registry.each.select { |m, _p| m.label == "tail => nil" }.map { |_m, p| p.original_source }
    expect(tails).to(eq(["a - b"]))
  end

  describe "statement positions inside interpolation" do
    def scan(src, keys: Kimera::Operators::DEFAULT_KEYS)
      described_class.new(operators: Kimera::Operators.build(keys: keys))
        .source("def m(o)\n#{src}\nend\n", file: "interp.rb")
    end

    def deleted(src)
      scan(src).points.select { |p| p.operator.include?("statement_deletion") }.map(&:original_source)
    end

    it "does not delete the value an interpolation embeds, in any interpolating literal" do
      src = <<~'RUBY'
        log "a #{o.inspect} b"
        s = :"s#{o.name}"
        t = `echo #{o.cmd}`
        r = /x#{o.pat}y/
        h = <<~TXT
          hi #{o.who}
        TXT
      RUBY
      expect(deleted(src)).to(eq(["log \"a \#{o.inspect} b\""]))
    end

    it "still deletes the discarded statements before an interpolation's value" do
      expect(deleted("\"\#{o.tick; o.tock}\"")).to(eq(["o.tick"]))
    end

    it "still deletes statements in a block inside an interpolation" do
      expect(deleted("\"\#{o.map { |x| x.save; x.id }}\"")).to(eq(["x.save", "x.id"]))
    end

    it "still gives other operators the expressions inside an interpolation" do
      registry = scan("\"\#{o.size > 1} \#{o.strip} \#{'t'}\"", keys: %w[comparison method_unwrap string_literal])
      points = registry.points.map { |p| [p.operator, p.original_source] }
      expect(points).to(include(["comparison", "o.size > 1"], %w[method_unwrap o.strip], ["string_literal", "'t'"]))
    end
  end

  describe "#walk" do
    def walker
      Kimera::RegistryScan::SourceFile.new("", file: "x.rb", operators: [], numbering: nil)
    end

    def cursor(**overrides)
      Kimera::RegistryWalking::Cursor.new(
        position: false, inside_def: false, in_pattern: false, def_body: false, defname: nil, embedded: false,
        **overrides
      )
    end

    it "ignores a non-node argument" do
      yielded = []
      walker.__send__(:walk, :not_a_node, cursor) { |n, *| yielded << n }
      expect(yielded).to(eq([]))
    end

    it "does not treat a bare statements list as a def body by default" do
      stmts = Prism.parse("a.b\nc.d\n").value.statements
      positions = []
      cur = cursor(inside_def: true)
      walker.__send__(:walk, stmts, cur) { |_n, c| positions << c.position }
      expect(positions).not_to(include(:tail))
    end
  end

  describe "#relative path boundary" do
    it "only strips the root at a directory boundary", :aggregate_failures do
      builder = described_class.new(root: "/app")
      expect(builder.__send__(:relative, "/application/x.rb")).to(eq("/application/x.rb"))
      expect(builder.__send__(:relative, "/app/models/x.rb")).to(eq("models/x.rb"))
      expect(builder.__send__(:relative, "/app")).to(eq("."))
    end
  end

  it "round-trips through JSON", :aggregate_failures do
    json = registry.to_json
    reloaded = Kimera::Registry.from_h(JSON.parse(json))
    expect(reloaded.count).to(eq(registry.count))
    expect(reloaded.points.first.original_source).to(eq(registry.points.first.original_source))
  end

  # A repeated or nil id would silently alias two mutation sites.
  describe "numbering" do
    def numbering = Kimera::RegistryScan::Numbering.new

    it "hands out its two sequences independently", :aggregate_failures do
      counter = numbering
      expect([counter.point, counter.point, counter.point]).to(eq([1, 2, 3]))
      expect([counter.mutant, counter.mutant]).to(eq([1, 2]))
    end

    it "numbers every point in a scan uniquely" do
      ids = registry.points.map(&:point_id)
      expect(ids).to(eq(ids.compact.uniq))
    end
  end

  # Different operators can meet on redundant code; one program is one mutant.
  describe "variants that leave the same program" do
    let(:operators) { Kimera::Operators.build(keys: ["all"]) }

    def labels(source)
      described_class.new(operators: operators).source(source, file: "x.rb").points.first.mutants.map(&:label)
    end

    it "keeps the first of the operators that meet", :aggregate_failures do
      expect(labels("def m(a)\n  a.to_s.to_s\nend\n")).to(eq(["delete `a.to_s.to_s`", "delete .to_s"]))
      expect(labels("def m\n  nil.respond_to?(:a)\nend\n")).to(eq(["delete `nil.respond_to?(:a)`", "drop arg `:a`"]))
      expect(labels("def m\n  Array(nil)\nend\n")).to(eq(["delete `Array(nil)`", "drop arg `nil`"]))
    end

    # `&` alone is not a program; the call is read where it stands.
    it "reads the node in its file", :aggregate_failures do
      expect(labels("def m(&)\n  f(1, 1, &)\nend\n")).to(eq(["delete `f(1, 1, &)`", "drop arg `1`"]))
      expect(labels("def m(a)\n  f(a, a)\n  a.map { it }\nend\n")).to(eq(["delete `f(a, a)`", "drop arg `a`"]))
    end

    # The parser gem rejects "\xff" in a UTF-8 file, where Prism reads it.
    it "keeps every variant of a file it can't render" do
      expect(labels("def m\n  f(1, 1)\n  \"\\xff\"\nend\n")).to(eq(["delete `f(1, 1)`"] + (["drop arg `1`"] * 2)))
    end
  end

  # Ruby reads a range literal it tests as a flip-flop; see Rewrite::Conditions.
  describe "variants that leave a range literal in a condition" do
    def labels(source, keys = ["all"])
      points = described_class.new(operators: Kimera::Operators.build(keys: keys)).source(source, file: "x.rb").points
      points.flat_map { |point| point.mutants.map(&:label) }
    end

    it "emits none", :aggregate_failures do
      expect(labels("def m(a, b)\n  !(a...b).cover?(a)\nend\n")).not_to(include("drop chain link `.cover?`"))
      expect(labels("def m(a, b)\n  1 if (a...b).to_a\nend\n")).not_to(include("delete .to_a"))
      expect(labels("def m(a, b)\n  (a...b).to_a\nend\n")).to(include("delete .to_a"))
    end

    it "leaves no point when every variant would" do
      expect(labels("def m(a, b)\n  1 if (a...b).to_a\nend\n", ["method_unwrap"])).to(be_empty)
    end
  end

  describe "tainting" do
    def spot
      Kimera::MutationPoint.new(
        point_id: 1, file: "x.rb", operator: "comparison", node_type: "call_node",
        location: Kimera::Location.new(
          start_offset: 10, span: 5, start_line: 1, start_column: 0, end_line: 1, end_column: 5
        ),
        original_source: "a > b", method_name: "m", mutants: []
      )
    end

    def range(from, to) = Kimera::Memoization::Range.new(from, to, "memoized via ||=", [])

    it "records the reason of the range covering it", :aggregate_failures do
      tainted = spot.taint!([range(0, 100)])
      expect(tainted.unsafe_reason).to(eq("memoized via ||="))
      expect(tainted.safe?).to(be(false))
    end

    it "leaves a point no range covers alone", :aggregate_failures do
      tainted = spot.taint!([range(100, 200)])
      expect(tainted.unsafe_reason).to(be_nil)
      expect(tainted.safe?).to(be(true))
    end

    it "keeps an unsafe reason it already carries" do
      claimed = spot
      claimed.unsafe!(Kimera::MutationPoint::CLASS_BODY_REASON)
      expect(claimed.taint!([range(0, 100)]).unsafe_reason).to(eq(Kimera::MutationPoint::CLASS_BODY_REASON))
    end
  end
end
