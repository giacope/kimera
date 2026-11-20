# frozen_string_literal: true

require "kimera/registry/builder"
require "tmpdir"

using PointFields

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
    operators = registry.to_a.map(&:operator).uniq
    expect(operators).to(include("comparison", "boolean_connective", "boolean_literal", "statement_deletion"))
  end

  it "captures the original source slice for each point", :aggregate_failures do
    point = registry.to_a.find { |p| p.original_source == "balance < limit" }
    expect(point).not_to(be_nil)
    expect(point.node_type).to(eq("call_node"))
  end

  it "records each point's enclosing method name", :aggregate_failures do
    point = registry.to_a.find { |p| p.original_source == "balance < limit" }
    expect(point.method_name).not_to(be_nil)
    expect(registry.to_a.map(&:method_name).uniq).to(all(be_a(String)))
  end

  it "produces boundary + negation variants for comparison operators" do
    point = registry.to_a.find { |p| p.original_source == "balance < limit" }
    labels = point.mutants.map(&:to_s)
    expect(labels).to(contain_exactly("< => <=", "< => >"))
  end

  it "only deletes named call statements, not pure comparisons", :aggregate_failures do
    deletions = registry.to_a.select { |p| p.operator == "statement_deletion" }
    sources = deletions.map(&:original_source)
    expect(sources).to(include("ledger.record(amount)"))
    expect(sources).not_to(include("balance >= 0"))
  end

  it "labels a statement-deletion mutant with the deleted statement's first line" do
    point = registry.to_a.find { |p| p.original_source == "ledger.record(amount)" }
    expect(point.mutants.map(&:to_s)).to(eq(["delete `ledger.record(amount)`"]))
  end

  it "assigns globally unique, deterministic mutant ids", :aggregate_failures do
    ids = registry.each.map { |m, _p| m.to_i }
    expect(ids).to(eq(ids.uniq))
    expect(ids).to(eq((1..ids.size).to_a))
  end

  it "produces no points for source that fails to parse" do
    registry = described_class.new.source(
      "def a(x, y)\n  x > y\nend\ndef broken(", file: "bad.rb"
    )
    expect(registry.to_a).to(eq([]))
  end

  it "marks only the def body's last statement as the implicit-return tail" do
    code = <<~RUBY
      def m(a, b)
        if a
          a + b
        end
        a - b
      end
    RUBY
    builder = described_class.new(operators: Kimera::Operators.build(keys: ["return_value"]))
    registry = builder.source(code, file: "tail.rb")
    tails = registry.each.select { |m, _p| m.to_s == "tail => nil" }.map { |_m, p| p.original_source }
    expect(tails).to(eq(["a - b"]))
  end

  describe "statement positions inside interpolation" do
    def scan(code, keys: Kimera::Operators.build.map(&:key))
      described_class.new(operators: Kimera::Operators.build(keys: keys))
        .source("def m(o)\n#{code}\nend\n", file: "interp.rb")
    end

    def deleted(code)
      scan(code).to_a.select { |p| p.operator.include?("statement_deletion") }.map(&:original_source)
    end

    it "does not delete the value an interpolation embeds, in any interpolating literal" do
      code = <<~'RUBY'
        log "a #{o.inspect} b"
        s = :"s#{o.name}"
        t = `echo #{o.cmd}`
        r = /x#{o.pat}y/
        h = <<~TXT
          hi #{o.who}
        TXT
      RUBY
      expect(deleted(code)).to(eq(["log \"a \#{o.inspect} b\""]))
    end

    it "still deletes the discarded statements before an interpolation's value" do
      expect(deleted("\"\#{o.tick; o.tock}\"")).to(eq(["o.tick"]))
    end

    it "still deletes statements in a block inside an interpolation" do
      expect(deleted("\"\#{o.map { |x| x.save; x.id }}\"")).to(eq(["x.save", "x.id"]))
    end

    it "still gives other operators the expressions inside an interpolation" do
      registry = scan("\"\#{o.size > 1} \#{o.strip} \#{'t'}\"", keys: %w[comparison method_unwrap string_literal])
      points = registry.to_a.map { |p| [p.operator, p.original_source] }
      expect(points).to(include(["comparison", "o.size > 1"], %w[method_unwrap o.strip], ["string_literal", "'t'"]))
    end
  end

  describe "the tail of a def" do
    def nils(code)
      operators = Kimera::Operators.build(keys: ["nil_literal"])
      scanned = described_class.new(operators: operators).source(code, file: "x.rb")
      scanned.to_a.flat_map { |point| point.mutants.map(&:to_s) }
    end

    it "is the def body's last statement, not the last of a statement list inside it", :aggregate_failures do
      expect(nils("def m(x)\n  a\n  nil\nend\n")).to(eq(["nil => Object.new"]))
      expect(nils("def m(x)\n  if x\n    a\n    nil\n  end\nend\n")).to(eq([]))
    end
  end

  describe "the file names it records" do
    def named(dir)
      app = File.join(dir, "app")
      files = [File.join(dir, "application", "x.rb"), File.join(app, "models", "x.rb")]
      files.each { |file| FileUtils.mkdir_p(File.dirname(file)) && File.write(file, "def a(x, y) = x > y\n") }
      registry = described_class.new(root: app).build([*files, app])
      [*registry.to_a.map(&:file), *JSON.parse(registry.to_json).fetch("unmutated").map { it.fetch("file") }]
    end

    it "strips the root only at a directory boundary, and names the root itself `.`" do
      Dir.mktmpdir { |dir| expect(named(dir)).to(eq(["models/x.rb", File.join(dir, "application", "x.rb"), "."])) }
    end
  end

  it "records the root it scanned: the working directory as `.`, another by its path", :aggregate_failures do
    root = ->(registry) { JSON.parse(registry.to_json).fetch("root") }
    expect(root.call(described_class.new.source("def a = 1\n", file: "a.rb"))).to(eq("."))
    expect(root.call(described_class.new(root: "/app").source("def a = 1\n", file: "a.rb"))).to(eq("/app"))
  end

  it "round-trips through JSON", :aggregate_failures do
    json = registry.to_json
    reloaded = Kimera::Registry.from_h(JSON.parse(json))
    expect(reloaded.each.count).to(eq(registry.each.count))
    expect(reloaded.to_a.first.original_source).to(eq(registry.to_a.first.original_source))
  end

  describe "numbering" do
    def numbering = Kimera::RegistryScan::Numbering.new

    it "hands out its two sequences independently", :aggregate_failures do
      counter = numbering
      expect([counter.point, counter.point, counter.point]).to(eq([1, 2, 3]))
      expect([counter.mutant, counter.mutant]).to(eq([1, 2]))
    end

    def first_id(paths) = described_class.new(root: "/").build(paths).each.map { |m, _p| m.to_i }.min

    it "numbers kimera's own mutants from OWN_FIRST, and a project's from 1" do
      Dir.mktmpdir do |dir|
        project = File.join(dir, "calc.rb").tap { |file| File.write(file, "def a(x, y) = x > y\n") }
        own = File.join(File.dirname(Kimera::Runtime::SOURCE_PATH), "registry", "numbering.rb")
        expect([first_id([project]), first_id([project, own])]).to(eq([1, described_class::OWN_FIRST]))
      end
    end

    it "numbers points and mutants from where it is told" do
      expect([numbering.point, Kimera::RegistryScan::Numbering.new(7).mutant]).to(eq([1, 7]))
    end

    it "numbers every point in a scan uniquely" do
      ids = registry.to_a.map(&:point_id)
      expect(ids).to(eq(ids.compact.uniq))
    end
  end

  describe "variants that leave the same program" do
    let(:operators) { Kimera::Operators.build(keys: ["all"]) }

    def labels(source)
      described_class.new(operators: operators).source(source, file: "x.rb").to_a.first.mutants.map(&:to_s)
    end

    it "keeps the first of the operators that meet", :aggregate_failures do
      expect(labels("def m(a)\n  a.to_s.to_s\nend\n")).to(eq(["delete `a.to_s.to_s`", "delete .to_s"]))
      expect(labels("def m\n  nil.respond_to?(:a)\nend\n")).to(eq(["delete `nil.respond_to?(:a)`", "drop arg `:a`"]))
      expect(labels("def m\n  Array(nil)\nend\n")).to(eq(["delete `Array(nil)`", "drop arg `nil`"]))
    end

    it "reads the node in its file", :aggregate_failures do
      expect(labels("def m(&)\n  f(1, 1, &)\nend\n")).to(eq(["delete `f(1, 1, &)`", "drop arg `1`"]))
      expect(labels("def m(a)\n  f(a, a)\n  a.map { it }\nend\n")).to(eq(["delete `f(a, a)`", "drop arg `a`"]))
    end

    it "compares the variants of a file with a regexp escape that is invalid UTF-8" do
      expect(labels("def m\n  f(1, 1)\n  /\\xff/\nend\n")).to(eq(["delete `f(1, 1)`", "drop arg `1`"]))
    end

    it "reads a file with a string escape that is invalid UTF-8" do
      expect(labels("def m\n  f(1, 1)\n  \"\\xff\"\nend\n")).to(eq(["delete `f(1, 1)`", "drop arg `1`"]))
    end
  end

  describe "variants that leave a range literal in a condition" do
    def labels(source, keys = ["all"])
      points = described_class.new(operators: Kimera::Operators.build(keys: keys)).source(source, file: "x.rb").to_a
      points.flat_map { |point| point.mutants.map(&:to_s) }
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

  describe "syntax-sensitive mutations" do
    cases = {
      "defined? arguments, but not adjacent expressions" => [
        "arithmetic", "1 + 2; defined?((3 + 4)); 5 + 6", [true, false, true]
      ],
      "nested defined? arguments" => ["arithmetic", "defined?(defined?((1 + 2)))", [false]],
      "replacing the whole defined? expression" => ["return_value", "defined?(name)", [true]],
      "an expression enclosing defined?" => ["arithmetic", "defined?(name) + 3", [true]],
      "flip-flop endpoints, but not the body or adjacent literals" => [
        "numeric_literal", "7; if 1...3; 9; end; 11", [true, false, false, true, true]
      ],
      "a bare capture name read before the regexp binds it" => [
        "boolean_connective", '/(?<x>a)/ =~ (x || "a"); true || false', [false, true]
      ],
      "an expression enclosing that capture" => [
        "boolean_connective", '(/(?<x>a)/ =~ (x || "a")) || false', [false, false]
      ],
      "an already-bound capture name" => ["boolean_connective", 'x = "a"; /(?<x>a)/ =~ (x || "a")', [true]],
      "an explicit method call sharing a capture name" => ["boolean_connective", '/(?<x>a)/ =~ (x() || "a")', [true]],
      "a different bare name" => ["boolean_connective", '/(?<x>a)/ =~ (y || "a")', [true]]
    }
    cases.each do |shape, (operator, code, safety)|
      it "routes #{shape} to the appropriate evaluation mode" do
        scanned = described_class.new(operators: Kimera::Operators.build(keys: [operator]))
          .source("def m; #{code}; end", file: "x.rb")
        expect(scanned.to_a.map(&:safe?)).to(eq(safety))
      end
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

    def taints(code)
      scanned = described_class.new(operators: Kimera::Operators.build(keys: ["comparison"])).source(code, file: "x.rb")
      scanned.to_a.map { |point| point.reasons(Kimera::Reason.unsafety) }
    end

    it "records the reason it is tainted with", :aggregate_failures do
      tainted = spot.tap { it.mark!(Kimera::Reason::Guarded.tainted("memoized via ||=")) }
      expect(tainted.reasons(Kimera::Reason.unsafety)).to(eq(["memoized via ||="]))
      expect(tainted.safe?).to(be(false))
    end

    it "finds the reason of a range covering the node, and none outside it" do
      expect(taints("def m\n  @x ||= a > b\nend\n\ndef n = c > d\n")).to(eq([["memoized via ||="], []]))
    end

    it "keeps an unsafe reason it already carries" do
      claimed = spot.tap { it.mark!(Kimera::Reason.body) }
      claimed.mark!(Kimera::Reason::Guarded.tainted("memoized via ||="))
      expect(claimed.reasons(Kimera::Reason.unsafety)).to(eq([Kimera::Reason::CLASS_BODY_REASON]))
    end
  end
end
