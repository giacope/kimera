# frozen_string_literal: true

require "kimera/support/unparse"

# Minitest turns on deprecation warnings when it loads, and parser (under
# unparser) trips them on every synthesis, flooding the run's stderr.
RSpec.describe(Kimera::Unparse) do
  it "round-trips source without letting unparser's warnings through", :aggregate_failures do
    allow(Unparser).to(receive(:parse).and_wrap_original { |original, source| warn("noise") || original.call(source) })
    allow(Unparser).to(receive(:unparse).and_wrap_original { |original, node| warn("noise") || original.call(node) })
    expect { expect(described_class.unparse(described_class.parse("a > b"))).to(eq("a > b")) }.not_to(output.to_stderr)
  end

  # unparser 0.9 only tracked locals from assignments and method parameters, so a
  # string interpolating any other local failed its round-trip check and took the
  # whole file down with it.
  describe(Kimera::Unparse::Binders) do
    def reemit(source) = Kimera::Unparse.unparse(Kimera::Unparse.parse(source))

    {
      "a case/in binding" => "def bid(value) = (case value; in chosen then \"\#{chosen}\"; end)",
      "an array pattern binding" => "def bid(v) = (case v; in [:parsed, chosen] then [\"\#{chosen}\", chosen]; end)",
      "a hash pattern binding" => "def bid(value) = (case value; in {chosen:} then \"\#{chosen}\"; end)",
      "a splat pattern binding" => "def bid(value) = (case value; in [*chosen] then \"\#{chosen}\"; end)",
      "a rightward assignment" => "def bid(value) = (value => chosen; \"\#{chosen}\")",
      "a block parameter" => "def bid(&chosen) = \"\#{chosen}\"",
      "a regexp named capture" => "def bid(value) = (/(?<chosen>.)/ =~ value; \"\#{chosen}\")"
    }.each do |binder, source|
      it "round-trips a string interpolating #{binder}" do
        expect(reemit(source)).to(include("\"\#{chosen}\""))
      end
    end

    it "binds no name for an anonymous block parameter", :aggregate_failures do
      anonymous = Kimera::Unparse.parse("def bid(&) = forward(&)").children[1].children.first
      expect(described_class.names(anonymous)).to(eq([]))
      expect(reemit("def bid(&) = forward(&)")).to(eq("def bid(&)\n  forward(&)\nend"))
    end

    # Under /x, a (?<name>) inside a comment names nothing, so the read stays a call.
    it "binds only the captures an extended regexp really names", :aggregate_failures do
      node = Kimera::Unparse.parse("/(?<real>.) # (?<fake>.)\n/x =~ value")
      expect(described_class.names(node)).to(eq([:real]))
      plain = Kimera::Unparse.parse("/(?<real>.) # (?<also>.)/ =~ value")
      expect(described_class.names(plain)).to(eq(%i[real also]))
    end

    it "binds nothing for nodes that bind nothing", :aggregate_failures do
      expect(described_class.names(Kimera::Unparse.parse("chosen = 1"))).to(eq([]))
      expect(described_class.names(Kimera::Unparse.parse("value"))).to(eq([]))
    end
  end

  # unparser 0.9 writes an array range endpoint as a %w/%i literal. It must come
  # back as the same AST, not just the same range: a string's interpolation is
  # written only once it parses back to the very node, so a parenthesized
  # endpoint (a begin node the tree lacks) left the string unwritable.
  describe(Kimera::Unparse::RangeEndpoints) do
    def reemit(source) = Kimera::Unparse.unparse(Kimera::Unparse.parse(source))

    {
      "([a, a]...a)" => "([a, a]...a)\n", "(0...[a, a])" => "(0...[a, a])\n",
      "[1, 2]..3" => "[1, 2]..3", "[1]..[2]" => "[1]..[2]", "[1]..nil" => "[1]..nil",
      "[1]..;" => "[1]..", "..[1]" => "..[1]", "[\"a b\", \"c]\"]..d" => "[\"a b\", \"c]\"]..d"
    }.each do |source, written|
      it "writes `#{source}` with its array endpoint as an array literal" do
        expect(reemit(source)).to(eq(written))
      end
    end

    it "writes a string interpolating a range with array endpoints", :aggregate_failures do
      source = "def m(a) = \"x\#{([]...[a]).to_s.size}y\""
      expect(reemit(source)).to(include("\"x\#{([]...[a]).to_s.size}y\""))
      expect(Kimera::Unparse.parse(reemit(source))).to(eq(Kimera::Unparse.parse(source)))
    end

    it "leaves other endpoints as unparser writes them", :aggregate_failures do
      expect(reemit("1..2")).to(eq("1..2"))
      expect(reemit("..2")).to(eq("..2"))
      expect(reemit("a...")).to(eq("a..."))
      expect(reemit("0...(1..2)")).to(eq("0...(1..2)"))
    end
  end

  # A mutated tree lacks the parentheses its new operator needs: with the inner
  # && of `x = a && b && c` swapped to ||, unparser wrote `x = a || b && c`.
  describe(Kimera::Unparse::Grouping) do
    # The tree as a mutation can leave it: no begin node for any parentheses.
    def bare(node, interpolated: false)
      return node unless node.is_a?(Parser::AST::Node)
      return bare(node.children[0]) if node.type == :begin && node.children.one? && !interpolated
      node.updated(nil, node.children.map { |child| bare(child, interpolated: node.type == :dstr) })
    end

    # Each source's tree, stripped of its parentheses, and how it is written.
    {
      "a && (b || c)" => "a && (b || c)", "x = (a || b) && c" => "x = (a || b) && c",
      "a && (b && c)" => "a && (b && c)", "a || (b || c)" => "a || (b || c)",
      "a || b && c" => "a || b && c", "a && b || c" => "a && b || c", "!(a && b)" => "!(a && b)",
      "(a || b).foo" => "(a || b).foo", "(a && b)[1]" => "(a && b)[1]", "(a || b)&.foo" => "(a || b)&.foo",
      "a + (b || c)" => "a + (b || c)", "(a..b).to_s" => "(a..b).to_s", "(a && b)..c" => "a && b..c",
      "a..(b..c)" => "a..(b..c)", "a - (b + c)" => "a - (b + c)", "a - b + c" => "a - b + c",
      "a ** (b * c)" => "a ** (b * c)", "(-a) ** b" => "(-a) ** b", "-(a ** b)" => "-a ** b",
      "!(a ** b)" => "!(a ** b)", "(a ** b) ** c" => "(a ** b) ** c", "a ** (b ** c)" => "a ** b.**(c)",
      "(a == b) == c" => "(a == b) == c", "a + (-b)" => "a + b.-@", "(!a) + b" => "!a + b",
      "a ** (-b)" => "a ** b.-@", "!(-a)" => "!-a", "(a - b).+(*c)" => "(a - b).+(*c)",
      "(x = a).foo" => "(x = a).foo", "(a.b = c).d" => "(a.b=c).d", "(a[0] = b).c" => "(a[0] = b).c",
      "(a rescue b).c" => "(a rescue b).c", "(a in b) && c" => "(a in b) && c", "defined?(a).b" => "defined?(a).b",
      "\"x\#{(a || b) && c}y\"" => "\"x\#{(a || b) && c}y\""
    }.each do |source, written|
      it "writes `#{source}` as `#{written}` from its tree without parentheses", :aggregate_failures do
        tree = bare(Kimera::Unparse.parse(source))
        expect(Kimera::Unparse.unparse(tree)).to(eq(written))
        expect(bare(Kimera::Unparse.parse(written))).to(eq(tree))
      end
    end

    it "leaves a tree that needs no parentheses as it is" do
      tree = Kimera::Unparse.parse("a && b || c.foo(d + e * f) - g")
      expect(described_class.call(tree)).to(equal(tree))
    end

    # Every nesting two deep of connectives and operators, in each context,
    # reads back as the very tree it was written from.
    def trees(depth)
      return [s(:send, nil, :a)] if depth.zero?
      inner = trees(depth - 1)
      pairs = inner.product(inner)
      [
        inner.first, *%i[and or].flat_map { |type| pairs.map { |pair| s(type, *pair) } },
        *%i[+ **].flat_map { |operator| pairs.map { |(left, right)| s(:send, left, operator, right) } },
        *%i[! -@].flat_map { |operator| inner.map { |operand| s(:send, operand, operator) } }
      ]
    end

    def s(type, *children) = Parser::AST::Node.new(type, children)

    def contexts(tree) = [tree, s(:lvasgn, :x, tree), s(:send, tree, :foo), s(:dstr, s(:str, "x"), s(:begin, tree))]

    it "writes every nested connective and operator so it reads back as written", :aggregate_failures do
      trees(2).flat_map { |tree| contexts(tree) }.each do |node|
        expect(Kimera::Unparse.parse(Kimera::Unparse.unparse(node))).to(eq(described_class.call(node)), node.inspect)
      end
    end
  end

  # unparser 0.9 writes a sign right before a numeric literal, and Ruby reads
  # the sign as the literal's: `-(0.to_s)` as `-0.to_s`, which is `(-0).to_s`.
  # Parsed source keeps such parentheses as a begin node; a mutation can root a
  # chain at a literal without one (`--1.to_s`, `-1 => 0`), so these trees are
  # built by hand.
  describe(Kimera::Unparse::Numerals) do
    def self.s(type, *children) = Parser::AST::Node.new(type, children)

    def s(...) = self.class.s(...)

    def write(node) = Kimera::Unparse.unparse(node)

    def reemit(source) = write(Kimera::Unparse.parse(source))

    let(:one) { s(:send, s(:int, 1), :abs) }

    {
      "an integer" => [s(:int, 0), "-(0.to_s)"], "a float" => [s(:float, 1.5), "-(1.5.to_s)"],
      "a rational" => [s(:rational, 1r), "-(1r.to_s)"], "an imaginary" => [s(:complex, 1i), "-(1i.to_s)"],
      "a negative literal" => [s(:int, -1), "-(-1.to_s)"]
    }.each do |kind, (literal, written)|
      it "writes minus over a call on #{kind} with the call in parentheses" do
        expect(write(s(:send, s(:send, literal, :to_s), :-@))).to(eq(written))
      end
    end

    {
      "a longer chain" => [s(:send, s(:send, s(:int, 1), :abs), :to_s), "-(1.abs.to_s)"],
      "a safe navigation" => [s(:csend, s(:int, 1), :abs), "-(1&.abs)"],
      "an index" => [s(:index, s(:send, s(:int, 1), :abs), s(:int, 0)), "-(1.abs[0])"],
      "a block" => [s(:block, s(:send, s(:int, 1), :then), s(:args), nil), "-(1.then {\n})"],
      "a numbered block" => [s(:numblock, s(:send, s(:int, 1), :then), 1, s(:lvar, :_1)), "-(1.then {\n  _1\n})"],
      "an it block" => [s(:itblock, s(:send, s(:int, 1), :then), :it, s(:lvar, :it)), "-(1.then {\n  it\n})"],
      "a power" => [s(:send, s(:int, 2), :**, s(:int, 2)), "-(2 ** 2)"],
      "a minus over a chain" => [s(:send, s(:send, s(:int, 1), :abs), :-@), "-(-(1.abs))"]
    }.each do |shape, (operand, written)|
      it "writes minus over #{shape} rooted at a literal with the operand in parentheses" do
        expect(write(s(:send, operand, :-@))).to(eq(written))
      end
    end

    it "writes plus over a chain rooted at a literal with the chain in parentheses" do
      expect(write(s(:send, one, :+@))).to(eq("+(1.abs)"))
    end

    it "leaves other signs, and other operands, as unparser writes them", :aggregate_failures do
      expect(write(s(:send, one, :~))).to(eq("~1.abs"))
      expect(write(s(:send, one, :!))).to(eq("!1.abs"))
      expect(write(s(:send, s(:int, 1), :-@))).to(eq("-1"))
      expect(write(s(:send, s(:int, 1), :+@))).to(eq("++1"))
      expect(write(s(:send, s(:array, s(:int, 1)), :-@))).to(eq("-[1]"))
      expect(reemit("-a.abs")).to(eq("-a.abs"))
      expect(reemit("-(1)")).to(eq("-(1)"))
    end

    {
      "an integer" => [s(:int, -1), "(-1) ** 2"], "a float" => [s(:float, -0.0), "(-0.0) ** 2"],
      "a rational" => [s(:rational, -1r), "(-1r) ** 2"], "an imaginary" => [s(:complex, -1i), "(-1i) ** 2"]
    }.each do |kind, (literal, written)|
      it "writes #{kind} negative literal raised to a power in parentheses" do
        expect(write(s(:send, literal, :**, s(:int, 2)))).to(eq(written))
      end
    end

    it "leaves other bases and operators as unparser writes them", :aggregate_failures do
      expect(write(s(:send, s(:int, 2), :**, s(:int, -1)))).to(eq("2 ** -1"))
      expect(write(s(:send, s(:int, -1), :*, s(:int, 2)))).to(eq("-1 * 2"))
      expect(write(s(:send, s(:send, s(:int, -1), :abs), :**, s(:int, 2)))).to(eq("-1.abs ** 2"))
      expect(reemit("10 ** 3")).to(eq("10 ** 3"))
    end

    # What Ruby itself reads back, not only the text.
    it "writes code that evaluates like the tree", :aggregate_failures do
      expect(Object.new.instance_eval(write(s(:send, s(:send, s(:int, 1), :to_s), :-@)))).to(eq("1"))
      expect(Object.new.instance_eval(write(s(:send, s(:int, -1), :**, s(:int, 2))))).to(eq(1))
    end
  end
end
