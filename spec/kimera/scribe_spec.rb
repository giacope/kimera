# frozen_string_literal: true

require "kimera/scribe"

RSpec.describe(Kimera::Scribe) do
  def self.s(type, *children) = Parser::AST::Node.new(type, children)

  def s(...) = self.class.s(...)

  def write(node) = described_class.new(node).source

  def reemit(source) = write(described_class.parse(source))

  # The tree as a mutation can leave it: no begin node for any parentheses.
  def self.bare(node, interpolated: false)
    return node unless node.is_a?(Parser::AST::Node)
    return bare(node.children[0]) if node.type == :begin && node.children.one? && !interpolated
    node.updated(nil, node.children.map { |child| bare(child, interpolated: node.type == :dstr) })
  end

  def bare(...) = self.class.bare(...)

  describe ".parse" do
    it "reads source into the parser gem's tree, and nothing into nil", :aggregate_failures do
      expect(described_class.parse("a > b")).to(eq(s(:send, s(:send, nil, :a), :>, s(:send, nil, :b))))
      expect(described_class.parse("")).to(be_nil)
    end

    it "reads __FILE__ and __LINE__ as themselves, not as literals" do
      expect(described_class.parse("[__FILE__, __LINE__]")).to(eq(s(:array, s(:__FILE__), s(:__LINE__))))
    end

    it "raises on source Ruby rejects" do
      expect { described_class.parse("def (") }.to(raise_error(Parser::SyntaxError))
    end

    # Minitest turns on deprecation warnings when it loads, and the parser gem
    # trips them on every synthesis, flooding the run's stderr.
    it "keeps the parser's warnings out of the run's stderr" do
      grammar = Kimera::Scribe::Reading::GRAMMAR
      allow(grammar).to(receive(:new).and_wrap_original { |original, builder| warn("noise") || original.call(builder) })
      expect { described_class.parse("a > b") }.not_to(output.to_stderr)
    end
  end

  # Ruby and Prism read "\xFF" in a UTF-8 file as that byte, but the parser
  # gem's builder rejected the literal, so one (as in Lobsters' avatar sniffing)
  # left its whole file unmutatable.
  describe "a string escape that is invalid UTF-8" do
    let(:source) { 'def jpeg?(data) = data.start_with?("\xFF\xD8\xFF".b)' }

    it "parses to the bytes Ruby reads and writes them back as escapes", :aggregate_failures do
      tree = described_class.parse(source)
      literal = tree.children.last.children.last.children.first
      expect(literal.children.first.bytes).to(eq([0xFF, 0xD8, 0xFF]))
      expect(write(tree)).to(eq("def jpeg?(data)\n  data.start_with?(\"\\xFF\\xD8\\xFF\".b)\nend"))
    end

    it "writes it back interpolated" do
      interpolated = %("x\#{"\\xFF"}y")
      expect(reemit(interpolated)).to(eq(interpolated))
    end

    it "still rejects what Ruby rejects, as an escape invalid in a regexp" do
      expect { described_class.parse('/\xFF/') }
        .to(raise_error(Parser::SyntaxError, %r{invalid multibyte escape: /\\xFF/}))
    end

    # unparser wrote a command string's parts as they are, so the escape came
    # back a raw byte and the file no longer loaded.
    it "writes a command string's byte back as an escape", :aggregate_failures do
      written = reemit("`printf \\xFE\#{name}`")
      expect(written).to(eq("`printf \\xFE\#{name}`"))
      expect(written).to(be_valid_encoding)
    end

    # unparser could not write such a byte back into a plain heredoc.
    it "writes a heredoc's byte back as an escape, the tree unchanged" do
      heredoc = "x = <<~TEXT\n  \\xFF\n  end \#{y}\nTEXT\n"
      expect(reemit(heredoc)).to(eq("x = \"\\xFF\nend \#{y}\\n\""))
    end
  end

  # unparser 0.9 only tracked locals from assignments and method parameters, so
  # a string interpolating any other local failed its round-trip check and took
  # the whole file down with it.
  describe "locals bound by patterns, captures and block parameters" do
    {
      "a case/in binding" => "def bid(value) = (case value; in chosen then \"\#{chosen}\"; end)",
      "an array pattern binding" => "def bid(v) = (case v; in [:parsed, chosen] then [\"\#{chosen}\", chosen]; end)",
      "a hash pattern binding" => "def bid(value) = (case value; in {chosen:} then \"\#{chosen}\"; end)",
      "a splat pattern binding" => "def bid(value) = (case value; in [*chosen] then \"\#{chosen}\"; end)",
      "a rightward assignment" => "def bid(value) = (value => chosen; \"\#{chosen}\")",
      "a block parameter" => "def bid(&chosen) = \"\#{chosen}\"",
      "a regexp named capture" => "def bid(value) = (/(?<chosen>.)/ =~ value; \"\#{chosen}\")",
      "a rescued exception" => "def bid = (begin; go; rescue => chosen; \"\#{chosen}\"; end)",
      "a for loop" => "def bid(list) = (for chosen in list do; end; \"\#{chosen}\")"
    }.each do |binder, source|
      it "writes a string interpolating #{binder}" do
        expect(described_class.parse(reemit(source))).to(eq(described_class.parse(source)))
      end
    end

    it "writes an anonymous block parameter" do
      expect(reemit("def bid(&) = forward(&)")).to(eq("def bid(&)\n  forward(&)\nend"))
    end

    # Under /x, a (?<name>) inside a comment names nothing, so the read stays a call.
    it "binds only the captures an extended regexp really names", :aggregate_failures do
      expect(reemit("/(?<real>.) # (?<fake>.)\n/x =~ value; real; fake"))
        .to(eq("/(?<real>.) # (?<fake>.)\n/x =~ value\nreal\nfake\n"))
      expect { write(described_class.parse("/(?<real>.) # (?<fake>.)\n/x =~ value; fake").children.last) }
        .not_to(raise_error)
    end

    # A guard that replaces the regexp of `/(?<n>.)/ =~ s` unbinds `n`, so the
    # body's read of it would come back a method call: the tree has no source.
    it "binds no capture when a guard stands where the regexp was" do
      pattern = s(:regexp, s(:str, "(?<n>.)"), s(:regopt))
      guarded = s(:if, s(:send, nil, :on?), pattern, pattern)
      tree = s(:begin, s(:match_with_lvasgn, guarded, s(:send, nil, :s)), s(:lvar, :n))
      expect { write(tree) }.to(raise_error(Kimera::Scribe::Unbound, /read of n/))
    end

    it "refuses a read of a local nothing binds" do
      tree = s(:begin, s(:send, s(:regexp, s(:str, "(?<n>.)"), s(:regopt)), :=~, s(:send, nil, :s)), s(:lvar, :n))
      expect { write(tree) }.to(raise_error(Kimera::Scribe::Unbound, /read of n/))
    end

    it "calls a method a local shadows with parentheses", :aggregate_failures do
      tree = s(:begin, s(:lvasgn, :name, s(:int, 1)), s(:send, nil, :name), s(:send, nil, :Name))
      expect(write(tree)).to(eq("name = 1\nname()\nName()\n"))
      expect(described_class.parse(write(tree))).to(eq(tree))
    end

    it "writes a modifier where the body binds a local its condition reads", :aggregate_failures do
      expect(reemit("a = 1 if a.nil?")).to(eq("a = 1 if a.nil?"))
      expect(reemit("a = b while a")).to(eq("a = b while a"))
      expect(reemit("if a.nil?\n  b = 1\nend")).to(eq("if a.nil?\n  b = 1\nend"))
    end
  end

  # unparser 0.9 wrote an array range endpoint as a %w/%i literal, raising on
  # any other element and changing `["a b"]` into `%w[a b]`.
  describe "array range endpoints" do
    {
      "([a, a]...a)" => "([a, a]...a)\n", "(0...[a, a])" => "(0...[a, a])\n",
      "[1, 2]..3" => "[1, 2]..3", "[1]..[2]" => "[1]..[2]", "[1]..nil" => "[1]..nil",
      "[1]..;" => "[1]..", "..[1]" => "..[1]", "[\"a b\", \"c]\"]..d" => "[\"a b\", \"c]\"]..d"
    }.each do |source, written|
      it "writes `#{source}` with its array endpoint as an array literal" do
        expect(reemit(source)).to(eq(written))
      end
    end

    it "writes a string interpolating a range with array endpoints" do
      expect(reemit("def m(a) = \"x\#{([]...[a]).to_s.size}y\"")).to(include("\"x\#{([]...[a]).to_s.size}y\""))
    end

    it "ends an endless range that is not the last statement" do
      expect(reemit("a = 1..; b")).to(eq("a = 1..;\nb\n"))
    end
  end

  # The parser reads `|(name)|` and `|name|` as the same procarg0 node, told
  # apart only by the location of the parentheses. Written without them, a
  # block handed ["a"] binds the whole array instead of "a": hashira's
  # `text.scan(RE) { |(name)| ... }` went red under kimera, unmutated.
  describe "a destructuring block parameter" do
    it "keeps the parentheses of a one-name destructuring block parameter", :aggregate_failures do
      expect(reemit("x.each { |(a)| a }")).to(eq("x.each { |(a)|\n  a\n}"))
      expect(reemit("x.each { |(a), b| a }")).to(eq("x.each { |(a), b|\n  a\n}"))
      expect(reemit("x.each { |(a, b)| a }")).to(eq("x.each { |(a, b)|\n  a\n}"))
    end

    it "writes a plain block parameter, and one built with no source, plainly", :aggregate_failures do
      expect(reemit("x.each { |a| a }")).to(eq("x.each { |a|\n  a\n}"))
      expect(reemit("x.each { |a,| a }")).to(eq("x.each { |a,|\n  a\n}"))
      built = s(:block, s(:send, nil, :x), s(:args, s(:procarg0, s(:arg, :a))), s(:lvar, :a))
      expect(write(built)).to(eq("x { |a|\n  a\n}"))
    end
  end

  # A mutated tree lacks the parentheses its new operator needs: with the inner
  # && of `x = a && b && c` swapped to ||, unparser wrote `x = a || b && c`.
  describe "grouping a tree without parentheses" do
    {
      "a && (b || c)" => "a && (b || c)", "x = (a || b) && c" => "x = (a || b) && c",
      "a && (b && c)" => "a && (b && c)", "a || (b || c)" => "a || (b || c)",
      "a || b && c" => "a || b && c", "a && b || c" => "a && b || c", "!(a && b)" => "!(a && b)",
      "(a || b).foo" => "(a || b).foo", "(a && b)[1]" => "(a && b)[1]", "(a || b)&.foo" => "(a || b)&.foo",
      "a + (b || c)" => "a + (b || c)", "(a..b).to_s" => "(a..b).to_s", "(a && b)..c" => "a && b..c",
      "a..(b..c)" => "a..(b..c)", "a - (b + c)" => "a - (b + c)", "a - b + c" => "a - b + c",
      "a ** (b * c)" => "a ** (b * c)", "(-a) ** b" => "(-a) ** b", "-(a ** b)" => "-a ** b",
      "!(a ** b)" => "!(a ** b)", "(a ** b) ** c" => "(a ** b) ** c", "a ** (b ** c)" => "a ** b ** c",
      "(a == b) == c" => "(a == b) == c", "a + (-b)" => "a + -b", "(!a) + b" => "!a + b",
      "a ** (-b)" => "a ** -b", "!(-a)" => "!-a", "(a - b).+(*c)" => "(a - b).+(*c)",
      "(x = a).foo" => "(x = a).foo", "(a.b = c).d" => "(a.b = c).d", "(a[0] = b).c" => "(a[0] = b).c",
      "(a rescue b).c" => "(a rescue b).c", "(a in b) && c" => "(a in b) && c", "defined?(a).b" => "defined?(a).b",
      "\"x\#{(a || b) && c}y\"" => "\"x\#{(a || b) && c}y\"", "(a && b = c) || d" => "a && (b = c) || d"
    }.each do |source, written|
      it "writes `#{source}` as `#{written}` from its tree without parentheses", :aggregate_failures do
        tree = bare(described_class.parse(source))
        expect(write(tree)).to(eq(written))
        expect(bare(described_class.parse(written))).to(eq(tree))
      end
    end

    it "writes source back as it reads, keeping its own parentheses" do
      source = "a && b || c.foo(d + e * f) - (g)"
      expect(reemit(source)).to(eq(source))
    end

    # Every nesting two deep of connectives and operators, in each context,
    # reads back as the very tree it was written from.
    def trees(depth)
      return [s(:send, nil, :a)] if depth.zero?
      inner = trees(depth - 1)
      pairs = inner.product(inner)
      [inner.first, *connected(pairs), *operated(pairs), *prefixed(inner)]
    end

    def connected(pairs) = %i[and or].flat_map { |type| pairs.map { |pair| s(type, *pair) } }

    def operated(pairs) = %i[+ **].flat_map { |operator| pairs.map { |(left, right)| s(:send, left, operator, right) } }

    def prefixed(inner) = %i[! -@].flat_map { |operator| inner.map { |operand| s(:send, operand, operator) } }

    def contexts(tree) = [tree, s(:lvasgn, :x, tree), s(:send, tree, :foo), s(:dstr, s(:str, "x"), s(:begin, tree))]

    it "writes every nested connective and operator so it reads back as written", :aggregate_failures do
      trees(2).flat_map { |tree| contexts(tree) }.each do |node|
        expect(bare(described_class.parse(write(node)))).to(eq(bare(node)), node.inspect)
      end
    end

    # Every nesting two deep of calls, blocks, powers and signs over numeric
    # literals, in each context, reads back as the very tree it was written
    # from. A sign straight over a literal is left out: `-1` reads back as the
    # literal -1, the same number.
    def numerals(depth)
      return [s(:int, 2), s(:int, -2)] if depth.zero?
      inner = numerals(depth - 1)
      [*inner, *powered(inner), *chained(inner), *blocked(inner), *signed(inner)]
    end

    def powered(inner) = inner.product(inner).map { |(left, right)| s(:send, left, :**, right) }

    def chained(inner)
      inner.flat_map { |base| [s(:send, base, :abs), s(:csend, base, :abs), s(:index, base, s(:int, 1))] }
    end

    def blocked(inner) = inner.map { |base| s(:block, s(:send, base, :then), s(:args), nil) }

    def signed(inner)
      signable = inner.reject { |operand| operand.type == :int }
      signable.product(%i[-@ +@]).map { |(operand, sign)| s(:send, operand, sign) }
    end

    it "writes every nested sign, power and call on a literal so it reads back as written", :aggregate_failures do
      numerals(2).flat_map { |tree| contexts(tree) }.each do |node|
        expect(bare(described_class.parse(write(node)))).to(eq(bare(node)), node.inspect)
      end
    end
  end

  # unparser 0.9 wrote a sign right before a numeric literal, and Ruby reads
  # the sign as the literal's: `-(0.to_s)` as `-0.to_s`, which is `(-0).to_s`.
  describe "a sign before a numeric literal" do
    let(:one) { s(:send, s(:int, 1), :abs) }

    {
      "an integer" => [s(:int, 0), "-(0.to_s)"], "a float" => [s(:float, 1.5), "-(1.5.to_s)"],
      "a rational" => [s(:rational, 1r), "-(1r.to_s)"], "an imaginary" => [s(:complex, 1i), "-(1i.to_s)"],
      "a negative literal" => [s(:int, -1), "--1.to_s"]
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
      "a power" => [s(:send, s(:int, 2), :**, s(:int, 2)), "-(2 ** 2)"]
    }.each do |shape, (operand, written)|
      it "writes minus over #{shape} rooted at a literal with the operand in parentheses" do
        expect(write(s(:send, operand, :-@))).to(eq(written))
      end
    end

    it "writes plus over a chain rooted at a literal with the chain in parentheses" do
      expect(write(s(:send, one, :+@))).to(eq("+(1.abs)"))
    end

    it "writes a sign over a signed chain with only the chain in parentheses" do
      expect(write(s(:send, s(:send, one, :-@), :-@))).to(eq("--(1.abs)"))
    end

    it "writes other signs, and other operands, as they read" do
      nodes = [
        s(:send, one, :~), s(:send, one, :!), s(:send, s(:int, 1), :-@), s(:send, s(:int, 1), :+@),
        s(:send, s(:array, s(:int, 1)), :-@), s(:csend, one, :-@)
      ]
      expect(nodes.map { |node| write(node) }).to(eq(["~1.abs", "!1.abs", "-1", "+1", "-[1]", "1.abs&.-@"]))
    end

    it "re-emits a negated call and a parenthesized literal as written" do
      expect([reemit("-a.abs"), reemit("-(1)")]).to(eq(["-a.abs", "-(1)"]))
    end

    {
      "an integer" => [s(:int, -1), "(-1) ** 2"], "a float" => [s(:float, -0.0), "(-0.0) ** 2"],
      "a rational" => [s(:rational, -1r), "(-1r) ** 2"], "an imaginary" => [s(:complex, -1i), "(-1i) ** 2"]
    }.each do |kind, (literal, written)|
      it "writes #{kind} negative literal raised to a power in parentheses" do
        expect(write(s(:send, literal, :**, s(:int, 2)))).to(eq(written))
      end
    end

    it "writes other bases and operators as they read", :aggregate_failures do
      expect(write(s(:send, s(:int, 2), :**, s(:int, -1)))).to(eq("2 ** -1"))
      expect(write(s(:send, s(:int, -1), :*, s(:int, 2)))).to(eq("-1 * 2"))
      expect(write(s(:send, s(:send, s(:int, -1), :abs), :**, s(:int, 2)))).to(eq("-1.abs ** 2"))
      expect(write(s(:send, s(:str, "-a"), :**, s(:int, 2)))).to(eq("\"-a\" ** 2"))
      expect(reemit("10 ** 3")).to(eq("10 ** 3"))
    end

    # What Ruby itself reads back, not only the text.
    it "writes code that evaluates like the tree", :aggregate_failures do
      expect(Object.new.instance_eval(write(s(:send, s(:send, s(:int, 1), :to_s), :-@)))).to(eq("1"))
      expect(Object.new.instance_eval(write(s(:send, s(:int, -1), :**, s(:int, 2))))).to(eq(1))
    end

    {
      "minus over a chain" => [s(:send, s(:send, s(:int, 1), :abs), :-@), "\"x\#{-(1.abs)}\"", "x-1"],
      "a negative literal raised to a power" => [s(:send, s(:int, -2), :**, s(:int, 2)), "\"x\#{(-2) ** 2}\"", "x4"]
    }.each do |shape, (tree, written, value)|
      it "writes #{shape} inside an interpolation", :aggregate_failures do
        expect(write(s(:dstr, s(:str, "x"), s(:begin, tree)))).to(eq(written))
        expect(Object.new.instance_eval(written)).to(eq(value))
      end
    end
  end

  # unparser refused, with "Unparser cannot round trip this node", any string
  # it could not prove would read back: Kimera spliced and coalesced string
  # parts around it, and dropped what was left.
  describe "interpolated strings of any shape" do
    def evaluates(node) = Object.new.instance_eval(write(node))

    {
      "statements in one interpolation" => [s(:dstr, s(:begin, s(:int, 1), s(:int, 2))), "\"\#{1; 2}\"", "2"],
      "an if node straight in a string" => [
        s(
          :dstr, s(:str, "a"),
          s(:if, s(:true), s(:str, "b"), s(:str, "c"))
        ), "\"a\#{if true\n  \"b\"\nelse\n  \"c\"\nend}\"", "ab"
      ],
      "a string in a string" => [
        s(:dstr, s(:str, "a"), s(:dstr, s(:str, "b"), s(:begin, s(:int, 1)))),
        "\"a\" \"b\#{1}\"", "ab1"
      ],
      "adjacent plain parts" => [s(:dstr, s(:str, "a"), s(:str, "b"), s(:begin, s(:int, 1))), "\"ab\#{1}\"", "ab1"],
      "an empty part" => [s(:dstr, s(:str, ""), s(:begin, s(:int, 1)), s(:str, "")), "\"\#{1}\"", "1"],
      "a lone part" => [s(:dstr, s(:str, "a")), "\"a\"", "a"],
      "no parts" => [s(:dstr), "\"\"", ""],
      "a variable read straight" => [s(:dstr, s(:ivar, :@a), s(:str, "b")), "\"\#{@a}b\"", "b"],
      "a variable read before a stop" => [s(:dstr, s(:ivar, :@a), s(:str, ".")), "\"\#@a.\"", "."],
      "a hash sign before an interpolation" => [s(:dstr, s(:str, "#"), s(:begin, s(:int, 1))), "\"#\#{1}\"", "#1"],
      "a hash sign before a brace" => [s(:dstr, s(:str, "#"), s(:str, "{a}")), "\"#\" \"{a}\"", "\#{a}"]
    }.each do |shape, (node, written, value)|
      it "writes #{shape}", :aggregate_failures do
        expect(write(node)).to(eq(written))
        expect(evaluates(node)).to(eq(value))
      end
    end

    it "keeps the lines of a heredoc as the parts the parser reads" do
      source = "x = <<~TEXT\n  a\n  b \#{c}\nTEXT\n"
      expect(
        [
          reemit(source),
          described_class.parse(reemit(source))
        ]
      ).to(eq(["x = \"a\nb \#{c}\\n\"", described_class.parse(source)]))
    end

    it "keeps juxtaposed strings juxtaposed" do
      expect(reemit("\"a\" \"b\#{c}\" 'd'")).to(eq("\"a\" \"b\#{c}\" \"d\""))
    end

    # Merging a multi-line %r{}x's str parts left no delimiter unparser could
    # emit, which sank the whole file (mastodon lost 107 mutants to it).
    {
      "%r{\n  a/b   # a comment\n  \#{c}\n}x" => "%r{\n  a/b   # a comment\n  \#{c}\n}x",
      "%r{a/b}" => "%r{a/b}", "/a\\/b/" => "%r{a/b}", "%r{a\\}b}" => "/a\\}b/", "%r[a/{b}]" => "%r[a/{b}]"
    }.each do |source, written|
      it "writes `#{source}` with a delimiter its pattern does not use" do
        expect(reemit(source)).to(eq(written))
      end
    end

    it "escapes the slashes of a pattern that uses every delimiter" do
      expect(write(s(:regexp, s(:str, "/{[(<|!"), s(:regopt, :i)))).to(eq("/\\/{[(<|!/i"))
    end
  end

  # unparser wrote a guard after `return` as a keyword `if`, which Ruby reads
  # as a modifier, and `a || b and c` for a mutated chain.
  describe "keywords that read differently where they sit" do
    it "writes a condition after return as a ternary" do
      tree = s(:return, s(:if, s(:send, nil, :a), s(:int, 1), nil))
      expect(write(tree)).to(eq("return a ? 1 : nil"))
    end

    it "writes and/or over a jump with the keyword", :aggregate_failures do
      expect(reemit("a or return")).to(eq("a or return"))
      expect(reemit("x = (a || b and return)")).to(eq("x = (a || b and return)"))
    end

    it "writes and/or/not as the source spelled them", :aggregate_failures do
      expect(reemit("a and b || c")).to(eq("a and b || c"))
      expect(reemit("x if a and not b == c")).to(eq("if a and not b == c\n  x\nend"))
    end

    it "keeps an assignment that closes an operand in parentheses", :aggregate_failures do
      expect(reemit("if a && b = c then d end")).to(eq("if a && b = c\n  d\nend"))
      expect(write(s(:or, s(:and, s(:send, nil, :a), s(:lvasgn, :b, s(:int, 1))), s(:send, nil, :c))))
        .to(eq("a && (b = 1) || c"))
    end
  end

  # Every form, read and written back: the text is exact, and it reads back as the tree.
  describe "every form" do
    {
      "true" =>
        "true",
      "[nil, self, __FILE__, __LINE__, __ENCODING__]" =>
        "[nil, self, __FILE__, __LINE__, __ENCODING__]",
      "@a; @@b; $c; $1; $&" =>
        "@a\n@@b\n$c\n$1\n$&\n",
      "[1, -2, 1.5, -0.0, 1e+20, 3r, 1.5r, -0.125r, 2i, -1.5i, 2ri]" =>
        "[1, -2, 1.5, -0.0, 1.0e+20, 3r, 1.5r, -0.125r, 2i, -1.5i, 2ri]",
      "[:a, :\"a b\", :+, :[]=, :a?, :\"9\", :\"\u00E9\"]" =>
        "[:a, :\"a b\", :+, :[]=, :a?, :\"9\", :\"\\u{E9}\"]",
      "[\"a\\\"b\\\\c\", \"\\\#{x}\", \"\\e\\x01\", \"\u00E9\", \"\u200B\"]" =>
        "[\"a\\\"b\\\\c\", \"\\\#{x}\", \"\\e\\x01\", \"\\u{E9}\", \"\\u{200B}\"]",
      "'\\\#$x \\\#@y'" =>
        "\"\\\\\\\#$x \\\\\\\#@y\"",
      "\"a\#{b}c\#@d.\#$e\"" =>
        "\"a\#{b}c\#@d.\#$e\"",
      ":\"a\#{b}\"" =>
        ":\"a\#{b}\"",
      "`ls \#{a}`" =>
        "`ls \#{a}`",
      "/a\#{b}/imx" =>
        "/a\#{b}/imx",
      "/\#{a}/o" =>
        "/\#{a}/o",
      "A::B; ::C; a::D" =>
        "A::B\n::C\na::D\n",
      "[1, *a, [2]]" =>
        "[1, *a, [2]]",
      "{}" =>
        "{}",
      "{ a: 1, \"b c\": 2, \"d\#{e}\": 3, 4 => 5, **f }" =>
        "{ a: 1, \"b c\": 2, \"d\#{e}\": 3, 4 => 5, **f }",
      "f(a:, **b, &c)" =>
        "f(a:, **b, &c)",
      "a = 1; f(a:)" =>
        "a = 1\nf(a:)\n",
      "def m(*, **, &) = f(*, **, &)" =>
        "def m(*, **, &)\n  f(*, **, &)\nend",
      "def m(...) = n(...)" =>
        "def m(...)\n  n(...)\nend",
      "1..2; ..3; 4...; (a..)" =>
        "1..2\n..3\n4...;\n(a..)\n",
      "a = b = c" =>
        "a = b = c",
      "a, (b, *c), * = d" =>
        "a, (b, *c), * = d",
      "a, = b" =>
        "a, = b",
      "*a, b = c" =>
        "*a, b = c",
      "a.b, c[0] = d" =>
        "a.b, c[0] = d",
      "a += 1; b ||= 2; c &&= 3" =>
        "a += 1\nb ||= 2\nc &&= 3\n",
      "a.b += 1; a&.b ||= 2; a[0] &&= 3; A::B ||= 4" =>
        "a.b += 1\na&.b ||= 2\na[0] &&= 3\nA::B ||= 4\n",
      "a.b = 1; a&.c = 2; a[0] = 3; A::D = 4; $g = 5; @@h = 6" =>
        "a.b = 1\na&.c = 2\na[0] = 3\nA::D = 4\n$g = 5\n@@h = 6\n",
      "x = a rescue b" =>
        "x = a rescue b",
      "a.b(c).d&.e(f)" =>
        "a.b(c).d&.e(f)",
      "a.(); a.[](1); a[]; a[1, 2]; a.+(b, c); a.+" =>
        "a.call\na.[](1)\na[]\na[1, 2]\na.+(b, c)\na.+\n",
      "-a; +a; !a; ~a; a.-@(b)" =>
        "-a\n+a\n!a\n~a\na.-@(b)\n",
      "a + b * c ** d / e % f - g << h >> i & j | k ^ l" =>
        "a + b * c ** d / e % f - g << h >> i & j | k ^ l",
      "a < b; a <= b; a > b; a >= b; a <=> b; a == b; a === b; a != b; a =~ b; a !~ b" =>
        "a < b\na <= b\na > b\na >= b\na <=> b\na == b\na === b\na != b\na =~ b\na !~ b\n",
      "foo; foo(); Foo(); a.foo; foo(1, 2)" =>
        "foo\nfoo\nFoo()\na.foo\nfoo(1, 2)\n",
      "x.each { |a| a }" =>
        "x.each { |a|\n  a\n}",
      "x.each { |a, (b, *c), *d, e:, f: 1, **g, &h| a }" =>
        "x.each { |a, (b, *c), *d, e:, f: 1, **g, &h|\n  a\n}",
      "x.each { |*| }" =>
        "x.each { |*|\n}",
      "x.each { |a; b| }" =>
        "x.each { |a; b|\n}",
      "->(a, b = 1) { a }" =>
        "->(a, b = 1) {\n  a\n}",
      "-> { }" =>
        "-> {\n}",
      "->(a; b) { }" =>
        "->(a; b) {\n}",
      "proc { _1 + _2 }" =>
        "proc {\n  _1 + _2\n}",
      "proc { it }" =>
        "proc {\n  it\n}",
      "foo do |x| a rescue b end" =>
        "foo do |x|\n  a\nrescue\n  b\nend",
      "super { }" =>
        "super {\n}",
      "super(a) { |x| }" =>
        "super(a) { |x|\n}",
      "a.+(b) { c }" =>
        "a.+(b) {\n  c\n}",
      "def m; end" =>
        "def m\nend",
      "def m(a, b = a, *c, d:, e: d, **f, &g); a; end" =>
        "def m(a, b = a, *c, d:, e: d, **f, &g)\n  a\nend",
      "def m(**nil); end" =>
        "def m(**nil)\nend",
      "def self.m; end" =>
        "def self.m\nend",
      "def a.m; end" =>
        "def a.m\nend",
      "def (a.b).m; end" =>
        "def (a.b).m\nend",
      "def m; a; rescue A, B => e; b; rescue; c; else; d; ensure; f; end" =>
        "def m\n  a\nrescue A, B => e\n  b\nrescue\n  c\nelse\n  d\nensure\n  f\nend",
      "def m; ensure; a; end" =>
        "def m\nensure\n  a\nend",
      "class A < B; def a; end; def b; end; end" =>
        "class A < B\n  def a\n  end\n\n  def b\n  end\nend\n",
      "class A::B; end" =>
        "class A::B\nend\n",
      "class << self; a; end" =>
        "class << self\n  a\nend\n",
      "module M; A = 1; end" =>
        "module M\n  A = 1\nend\n",
      "if a; b; end" =>
        "if a\n  b\nend",
      "if a; b; else; c; end" =>
        "if a\n  b\nelse\n  c\nend",
      "if a; b; elsif c; d; elsif e; f; else; g; end" =>
        "if a\n  b\nelsif c\n  d\nelsif e\n  f\nelse\n  g\nend",
      "unless a; b; end" =>
        "unless a\n  b\nend",
      "unless a; b; else; c; end" =>
        "if a\n  c\nelse\n  b\nend",
      "if a; else; c; end" =>
        "unless a\n  c\nend",
      "x = if a; b; else; c; end" =>
        "x = if a\n  b\nelse\n  c\nend",
      "a = 1 if a.nil?" =>
        "a = 1 if a.nil?",
      "a = 1 unless a" =>
        "a = 1 unless a",
      "if a; b; else; n = 1 if n; end" =>
        "if a\n  b\nelse\n  n = 1 if n\nend",
      "return a ? b : c" =>
        "return a ? b : c",
      "return a ? b = 1 : c" =>
        "return a ? b = 1 : c",
      "next; break 1; return 1, 2" =>
        "next\nbreak 1\nreturn 1, 2\n",
      "a && b || c" =>
        "a && b || c",
      "a and b or c" =>
        "a and b or c",
      "a and return" =>
        "a and return",
      "not a" =>
        "not a",
      "not (a and b)" =>
        "not (a and b)",
      "not(a and b)" =>
        "not(a and b)",
      "a if b and not c" =>
        "if b and not c\n  a\nend",
      "while a; b; end" =>
        "while a\n  b\nend",
      "until a; b; end" =>
        "until a\n  b\nend",
      "begin; a; end while b" =>
        "begin\n  a\nend while b",
      "begin; a; end until b" =>
        "begin\n  a\nend until b",
      "a = b while a.nil?" =>
        "a = b while a.nil?",
      "x = while a do b end" =>
        "x = while a\n  b\nend",
      "for a in b; c; end" =>
        "for a in b\n  c\nend",
      "for a, b in c; d; end" =>
        "for (a, b) in c\n  d\nend",
      "case a; when 1, 2; b; when *c; d; else; e; end" =>
        "case a\nwhen 1, 2\n  b\nwhen *c\n  d\nelse\n  e\nend",
      "case; when a; b; end" =>
        "case\nwhen a\n  b\nend",
      "case a; in [b, *c] then b; in [*, 2, *] unless g then 2; in [i,] then 5; in [*] then 10; end" =>
        "case a\nin [b, *c]\n  b\nin [*, 2, *] unless g\n  2\nin [i,]\n  5\nin [*]\n  10\nend",
      "case a; in {d:, e: 1, **f} if d then 1; in {} then 6; in {j: 1, **nil} then 7; end" =>
        "case a\nin { d:, e: 1, **f } if d\n  1\nin {}\n  6\nin { j: 1, **nil }\n  7\nend",
      "case a; in A | B => h then 3; in ^h then 4; in C(k, l) then 8; in C(m:) then 9; in ^(1 + 1) then 11; end" =>
        "case a\nin A | B => h\n  3\nin ^h\n  4\nin C(k, l)\n  8\nin C(m:)\n  9\nin ^(1 + 1)\n  11\nend",
      "case a; in 1; else; end" =>
        "case a\nin 1\nelse\nend",
      "a => b" =>
        "a => b",
      "a in b" =>
        "a in b",
      "begin; a; end" =>
        "begin\n  a\nend",
      "begin; a; b; end" =>
        "begin\n  a\n  b\nend",
      "begin; a; rescue; b; end" =>
        "begin\n  a\nrescue\n  b\nend",
      "x = begin; a; rescue A; b; end" =>
        "x = begin\n  a\nrescue A\n  b\nend",
      "x = begin; a; rescue; b; else; c; end" =>
        "x = begin\n  a\nrescue\n  b\nelse\n  c\nend",
      "x = begin; a; ensure; b; end" =>
        "x = begin\n  a\nensure\n  b\nend",
      "begin; rescue => e; e; end" =>
        "begin\nrescue => e\n  e\nend",
      "begin; a; rescue a ? B : C; b; end" =>
        "begin\n  a\nrescue a ? B : C\n  b\nend",
      "alias a b" =>
        "alias :a :b",
      "alias $a $b" =>
        "alias $a $b",
      "undef a, :b" =>
        "undef :a, :b",
      "BEGIN { a }" =>
        "BEGIN {\n  a\n}",
      "END { a }" =>
        "END {\n  a\n}",
      "if /x/; a; end" =>
        "if /x/\n  a\nend",
      "if a..b; c; end" =>
        "if a..b\n  c\nend",
      "if a...b; c; end" =>
        "if a...b\n  c\nend",
      "/(?<n>.)/ =~ s; n" =>
        "/(?<n>.)/ =~ s\nn\n",
      "/(?<n>.)\#{x}/ =~ s; n" =>
        "/(?<n>.)\#{x}/ =~ s\nn\n",
      "/(?<a>.) # (?<b>.)/ =~ v; b" =>
        "/(?<a>.) # (?<b>.)/ =~ v\nb\n",
      "yield; yield(a); super; super(); super(a); defined?(a)" =>
        "yield\nyield(a)\nsuper\nsuper()\nsuper(a)\ndefined?(a)\n",
      "x = (a and b)" =>
        "x = (a and b)",
      "a && (not b)" =>
        "a && (not b)",
      "x = (b = 1 if b)" =>
        "x = (b = 1 if b)",
      "x = <<~A\n  a\n    b\nA" =>
        "x = \"a\\n\" \"  b\\n\"",
      "\"#\" \"{a}\"" =>
        "\"#\" \"{a}\"",
      "\"a\" \"b\" \"c\"" =>
        "\"a\" \"b\" \"c\"",
      "\"a\\nb\#{c}d\"" =>
        "\"a\\nb\#{c}d\"",
      "`a\\`b`" =>
        "`a\\`b`",
      "%r{a/b}" =>
        "%r{a/b}",
      "\"\#{}\"\n" =>
        "\"\#{}\""
    }.each do |source, written|
      it "writes `#{source}` as `#{written}`", :aggregate_failures do
        expect(reemit(source)).to(eq(written))
        expect(described_class.parse(written)).to(eq(described_class.parse(source)))
      end
    end
  end

  # Trees no source reads as, written as Ruby reads them back.
  describe "trees a mutation can leave" do
    a, b, c, d, e = %i[a b c d e].map { |name| s(:send, nil, name) }
    {
      "no parts" => [s(:dstr), "\"\""],
      "an escaped hash sign before a brace" => [
        s(:dstr, s(:str, "#"), s(:str, "{a}"), s(:begin, s(:int, 1))), "\"\\\#{a}\#{1}\""
      ],
      "an interpolation beside a nested string" => [
        s(:dstr, s(:dstr, s(:str, "a"), s(:begin, s(:int, 1))), s(:begin, s(:int, 2))), "\"a\#{1}\" \"\#{2}\""
      ],
      "a setter with no receiver" => [s(:send, nil, :a=, s(:int, 1)), "self.a = 1"],
      "a destructuring parameter built with no source" => [
        s(:block, s(:send, nil, :x), s(:args, s(:procarg0, s(:arg, :a), s(:arg, :b))), nil), "x { |(a, b)|\n}"
      ],
      "a loop after return" => [s(:return, s(:while, a, b)), "return (while a\n  b\nend)"],
      "or over a jump, built with no source" => [s(:or, a, s(:return)), "a or return"],
      "and with not on its right" => [bare(described_class.parse("a && (not b)")), "a && (not b)"],
      "and as a value" => [bare(described_class.parse("x = (a and b)")), "x = (a and b)"],
      "a modifier as a value" => [bare(described_class.parse("x = (b = 1 if b)")), "x = (b = 1 if b)"],
      "not over a connective" => [bare(described_class.parse("not (a and b)")), "not(a and b)"],
      "a ternary with no middle" => [s(:return, s(:if, a, nil, b)), "return a ? nil : b"],
      "a ternary with a condition in the middle" => [
        s(:return, s(:if, a, s(:if, b, c, d), e)), "return a ? (if b\n  c\nelse\n  d\nend) : e"
      ],
      "a condition before an operator" => [s(:or, s(:if, a, b, c), d), "if a\n  b\nelse\n  c\nend || d"],
      "a condition after an operator" => [s(:or, d, s(:if, a, b, c)), "d || if a\n  b\nelse\n  c\nend"],
      "a condition as a receiver" => [s(:send, s(:if, a, b, c), :d), "if a\n  b\nelse\n  c\nend.d"],
      "a rescue modifier as an argument" => [
        s(:yield, s(:rescue, a, s(:resbody, nil, nil, b), nil)),
        "yield((a rescue b))"
      ],
      "an alternative of a binding pattern" => [
        s(:match_pattern, a, s(:match_alt, s(:match_as, s(:const, nil, :A), s(:match_var, :x)), s(:const, nil, :B))),
        "a => (A => x) | B"
      ],
      "a capture by an invalid pattern" => [s(:match_with_lvasgn, s(:regexp, s(:str, "("), s(:regopt)), b), "/(/ =~ b"],
      "a constant valued pair" => [s(:hash, s(:pair, s(:sym, :A), s(:const, nil, :A))), "{ A: A }"],
      "a complex number with a real part" => [s(:complex, Complex(1, 2)), "Complex(1, 2)"],
      "not a number" => [s(:float, Float::NAN), "Float::NAN"],
      "infinity" => [s(:array, s(:float, Float::INFINITY), s(:float, -Float::INFINITY)), "[Float::INFINITY, -Float::INFINITY]"],
      "a rational with no decimal" => [s(:rational, Rational(1, 3)), "Rational(1, 3)"],
      "a rational with a decimal" => [s(:rational, Rational(5, 2)), "2.5r"],
      "a string with bytes beside a character" => [
        s(:str, (+"\u00E9\xFF").force_encoding(Encoding::UTF_8)), "\"\\xC3\\xA9\\xFF\""
      ],
      "a binary string" => [s(:str, "\u00E9".b), "\"\\xC3\\xA9\""],
      "a loop that runs its body first, as a value" => [
        s(:lvasgn, :x, s(:while_post, b, s(:kwbegin, a))), "x = (begin\n  a\nend while b)"
      ],
      "a rescue of nothing, as a value" => [
        s(:lvasgn, :x, s(:rescue, nil, s(:resbody, nil, nil, b), nil)), "x = begin\nrescue\n  b\nend"
      ],
      "a rescue with two handlers, as a value" => [
        s(
          :lvasgn, :x,
          s(:rescue, a, s(:resbody, s(:array, s(:const, nil, :A)), nil, b), s(:resbody, nil, nil, c), nil)
        ),
        "x = begin\n  a\nrescue A\n  b\nrescue\n  c\nend"
      ],
      "a rescue with an else, as a value" => [
        s(:lvasgn, :x, s(:rescue, a, s(:resbody, nil, nil, b), c)), "x = begin\n  a\nrescue\n  b\nelse\n  c\nend"
      ],
      "a rescue of a class, as a value" => [
        s(:lvasgn, :x, s(:rescue, a, s(:resbody, s(:array, s(:const, nil, :A)), nil, b), nil)),
        "x = begin\n  a\nrescue A\n  b\nend"
      ],
      "a rescue binding the error, as a value" => [
        s(:lvasgn, :x, s(:rescue, a, s(:resbody, nil, s(:lvasgn, :e), b), nil)), "x = begin\n  a\nrescue => e\n  b\nend"
      ],
      "a rescue of a class, as an argument" => [
        s(:send, nil, :f, s(:rescue, a, s(:resbody, s(:array, s(:const, nil, :A)), nil, b), nil)),
        "f(begin\n  a\nrescue A\n  b\nend)"
      ],
      "an ensure, as a value" => [s(:lvasgn, :x, s(:ensure, a, b)), "x = begin\n  a\nensure\n  b\nend"]
    }.each do |shape, (tree, written)|
      it "writes #{shape}" do
        expect(write(tree)).to(eq(written))
      end
    end

    it "writes nothing for no tree" do
      expect(write(nil)).to(eq(""))
    end

    it "refuses a node type it does not know" do
      expect { write(s(:unknown)) }.to(raise_error(ArgumentError, "kimera cannot write a unknown node"))
    end
  end

  # Every file of kimera's own reads back as the very tree it was written from.
  it "writes kimera's own sources so they read back as the same tree", :aggregate_failures do
    Dir[File.expand_path("../../lib/**/*.rb", __dir__)].each do |file|
      tree = described_class.parse(File.read(file, encoding: Encoding::UTF_8))
      expect(described_class.parse(write(tree))).to(eq(tree), file)
    end
  end
end
