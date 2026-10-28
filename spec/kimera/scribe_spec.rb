# frozen_string_literal: true

require "kimera/scribe"
require "kimera/scribe/nodes"
require "kimera/rewrite/ast_walk"

RSpec.describe(Kimera::Scribe) do
  extend Kimera::Scribe::Nodes
  include Kimera::Scribe::Nodes

  def self.parse(source) = described_class.parse(source)

  def self.statement(source) = parse(source).statements.body.first

  # The tree as a mutation can leave it: no parentheses around a lone expression.
  def self.bare(node)
    Kimera::Rewrite::AstWalk.new(node).rebuild do |rebuilt|
      body = rebuilt.body if rebuilt.type == :parentheses_node
      body&.type == :statements_node && body.body.one? ? body.body.first : rebuilt
    end
  end

  def self.interpolated(*parts) = statement("\"a\#{b}\"").copy(parts: parts)

  def self.plain(text) = statement("\"a\#{b}\"").parts.first.copy(unescaped: text)

  def self.embedded(source) = statement("\"\#{#{source}}\"").parts.first

  def self.named(name) = statement("a").copy(name: name)

  def parse(...) = self.class.parse(...)

  def statement(...) = self.class.statement(...)

  def bare(...) = self.class.bare(...)

  def interpolated(...) = self.class.interpolated(...)

  def plain(...) = self.class.plain(...)

  def embedded(...) = self.class.embedded(...)

  def named(...) = self.class.named(...)

  def shape(node) = TreeShape.of(node)

  def write(node) = described_class.new(node).source

  def reemit(source) = write(parse(source))

  describe ".parse" do
    it "reads source into Prism's tree, and nothing into an empty program", :aggregate_failures do
      expect(statement("a > b")).to(have_attributes(type: :call_node, name: :>))
      expect([parse("").statements.body, write(parse(""))]).to(eq([[], ""]))
    end

    it "reads __FILE__ and __LINE__ as themselves, not as literals" do
      expect(statement("[__FILE__, __LINE__]").elements.map(&:type)).to(eq(%i[source_file_node source_line_node]))
    end

    it "raises on source Ruby rejects" do
      expect { parse("def (") }.to(raise_error(described_class::Unreadable))
    end
  end

  # Ruby and Prism read "\xFF" in a UTF-8 file as that byte, but the parser
  # gem's builder rejected the literal, so one (as in Lobsters' avatar sniffing)
  # left its whole file unmutatable.
  describe "a string escape that is invalid UTF-8" do
    let(:source) { 'def jpeg?(data) = data.start_with?("\xFF\xD8\xFF".b)' }

    it "parses to the bytes Ruby reads and writes them back as escapes", :aggregate_failures do
      literal = statement(source).body.body.first.arguments.arguments.first.receiver
      expect(literal.unescaped.bytes).to(eq([0xFF, 0xD8, 0xFF]))
      expect(reemit(source)).to(eq("def jpeg?(data)\n  data.start_with?(\"\\xFF\\xD8\\xFF\".b)\nend"))
    end

    it "writes it back interpolated" do
      interpolated = %("x\#{"\\xFF"}y")
      expect(reemit(interpolated)).to(eq(interpolated))
    end

    # Ruby rejects it only when it compiles the regexp, so the file still reads.
    it "reads a regexp escape that is invalid UTF-8 and writes it back" do
      expect(reemit('/\xFF/')).to(eq('/\xFF/'))
    end

    # unparser wrote a command string's parts as they are, so the escape came
    # back a raw byte and the file no longer loaded.
    it "writes a command string's byte back as an escape", :aggregate_failures do
      written = reemit("`printf \\xFE\#{name}`")
      expect(written).to(eq("`printf \\xFE\#{name}`"))
      expect(written).to(be_valid_encoding)
    end

    # unparser could not write such a byte back into a plain heredoc.
    it "writes a heredoc's byte back as an escape, the tree unchanged", :aggregate_failures do
      heredoc = "x = <<~TEXT\n  \\xFF\n  end \#{y}\nTEXT\n"
      expect(reemit(heredoc)).to(eq("x = \"\\xFF\\nend \#{y}\\n\""))
      expect(shape(parse(reemit(heredoc)))).to(eq(shape(parse(heredoc))))
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
        expect(shape(parse(reemit(source)))).to(eq(shape(parse(source))))
      end
    end

    it "writes an anonymous block parameter" do
      expect(reemit("def bid(&) = forward(&)")).to(eq("def bid(&)\n  forward(&)\nend"))
    end

    # Under /x, a (?<name>) inside a comment names nothing, so the read stays a call.
    it "binds only the captures an extended regexp really names", :aggregate_failures do
      expect(reemit("/(?<real>.) # (?<fake>.)\n/x =~ value; real; fake"))
        .to(eq("/(?<real>.) # (?<fake>.)\n/x =~ value\nreal\nfake\n"))
      expect { write(parse("/(?<real>.) # (?<fake>.)\n/x =~ value; fake").statements.body.last) }
        .not_to(raise_error)
    end

    # A guard that replaces the regexp of `/(?<n>.)/ =~ s` unbinds `n`, so the
    # body's read of it would come back a method call: the tree has no source.
    it "binds no capture when a guard stands where the regexp was" do
      capture, read = parse("/(?<n>.)/ =~ s; n").statements.body
      call = capture.call
      guarded = capture.copy(call: call.copy(receiver: branched(named(:on?), call.receiver, call.receiver)))
      expect { write(statements([guarded, read])) }.to(raise_error(described_class::Unbound, /read of n/))
    end

    it "refuses a read of a local nothing binds" do
      tree = statements([statement("/(?<n>.)/.match(s)"), local(:n)])
      expect { write(tree) }.to(raise_error(described_class::Unbound, /read of n/))
    end

    it "calls a method a local shadows with parentheses", :aggregate_failures do
      tree = statements([statement("name = 1"), named(:name), named(:Name)])
      expect(write(tree)).to(eq("name = 1\nname()\nName()\n"))
      expect(parse(write(tree)).statements.body.map { |node| [node.type, node.name] })
        .to(eq([%i[local_variable_write_node name], %i[call_node name], %i[call_node Name]]))
    end

    it "writes a modifier where the body binds a local its condition reads", :aggregate_failures do
      expect(reemit("a = 1 if a.nil?")).to(eq("a = 1 if a.nil?"))
      expect(reemit("a = b while a")).to(eq("a = b while a"))
      expect(reemit("if a.nil?\n  b = 1\nend")).to(eq("if a.nil?\n  b = 1\nend"))
    end

    # A block parameter's read in the condition is the block's own, not the body's.
    it "keeps a condition that reads a block parameter in front", :aggregate_failures do
      source = "if a.any? { |d| d.b }\n  d = 1\n  e\nend"
      expect(reemit(source)).to(eq("if a.any? { |d|\n  d.b\n}\n  d = 1\n  e\nend"))
      expect(shape(parse(reemit(source)))).to(eq(shape(parse(source))))
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

  # The parser gem read `|(name)|` and `|name|` as the same procarg0 node, told
  # apart only by the location of the parentheses. Written without them, a
  # block handed ["a"] binds the whole array instead of "a": hashira's
  # `text.scan(RE) { |(name)| ... }` went red under kimera, unmutated.
  describe "a destructuring block parameter" do
    it "keeps the parentheses of a one-name destructuring block parameter", :aggregate_failures do
      expect(reemit("x.each { |(a)| a }")).to(eq("x.each { |(a)|\n  a\n}"))
      expect(reemit("x.each { |(a), b| a }")).to(eq("x.each { |(a), b|\n  a\n}"))
      expect(reemit("x.each { |(a, b)| a }")).to(eq("x.each { |(a, b)|\n  a\n}"))
    end

    it "writes a plain block parameter plainly", :aggregate_failures do
      expect(reemit("x.each { |a| a }")).to(eq("x.each { |a|\n  a\n}"))
      expect(reemit("x.each { |a,| a }")).to(eq("x.each { |a,|\n  a\n}"))
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
        tree = bare(parse(source))
        expect(write(tree)).to(eq(written))
        expect(shape(bare(parse(written)))).to(eq(shape(tree)))
      end
    end

    it "writes source back as it reads, keeping its own parentheses" do
      source = "a && b || c.foo(d + e * f) - (g)"
      expect(reemit(source)).to(eq(source))
    end

    def joined(template, left, right) = statement(template).copy(left: left, right: right)

    def operation(operator, left, right)
      call = statement("a #{operator} a")
      call.copy(receiver: left, arguments: call.arguments.copy(arguments: [right]))
    end

    def over(template, receiver) = statement(template).copy(receiver: receiver)

    # Every nesting two deep of connectives and operators, in each context,
    # reads back as the very tree it was written from.
    def trees(depth)
      return [named(:a)] if depth.zero?
      inner = trees(depth - 1)
      pairs = inner.product(inner)
      [inner.first, *connected(pairs), *operated(pairs), *prefixed(inner)]
    end

    def connected(pairs) = ["a && a", "a || a"].flat_map { |template| pairs.map { |pair| joined(template, *pair) } }

    def operated(pairs) = %w[+ **].flat_map { |operator| pairs.map { |pair| operation(operator, *pair) } }

    def prefixed(inner) = %w[!a -a].flat_map { |template| inner.map { |operand| over(template, operand) } }

    def contexts(tree)
      [
        tree, statement("x = a").copy(value: tree), over("a.foo", tree),
        interpolated(plain("x"), embedded("a").copy(statements: statements([tree])))
      ]
    end

    def reread(node) = bare(statement(write(node)))

    it "writes every nested connective and operator so it reads back as written", :aggregate_failures do
      trees(2).flat_map { |tree| contexts(tree) }.each do |node|
        expect(shape(reread(node))).to(eq(shape(bare(node))), write(node))
      end
    end

    # Every nesting two deep of calls, blocks, powers and signs over numeric
    # literals, in each context, reads back as the very tree it was written
    # from. A sign straight over a literal is left out: `-1` reads back as the
    # literal -1, the same number.
    def numerals(depth)
      return [statement("2"), statement("-2")] if depth.zero?
      inner = numerals(depth - 1)
      [*inner, *powered(inner), *chained(inner), *blocked(inner), *signed(inner)]
    end

    def powered(inner) = inner.product(inner).map { |pair| operation("**", *pair) }

    def chained(inner) = inner.product(%w[a.abs a&.abs a[1]]).map { |(base, template)| over(template, base) }

    def blocked(inner) = inner.map { |base| over("a.then {}", base) }

    def signed(inner)
      signable = inner.reject { |operand| operand.type == :integer_node }
      signable.product(%w[-a +a]).map { |(operand, template)| over(template, operand) }
    end

    it "writes every nested sign, power and call on a literal so it reads back as written", :aggregate_failures do
      numerals(2).flat_map { |tree| contexts(tree) }.each do |node|
        expect(shape(reread(node))).to(eq(shape(bare(node))), write(node))
      end
    end
  end

  # unparser 0.9 wrote a sign right before a numeric literal, and Ruby reads
  # the sign as the literal's: `-(0.to_s)` as `-0.to_s`, which is `(-0).to_s`.
  describe "a sign before a numeric literal" do
    def unparenthesized(source) = bare(statement(source))

    {
      "a call on an integer" => ["-(0.to_s)", "-(0.to_s)"], "a call on a float" => ["-(1.5.to_s)", "-(1.5.to_s)"],
      "a call on a rational" => ["-(1r.to_s)", "-(1r.to_s)"], "a call on an imaginary" => ["-(1i.to_s)", "-(1i.to_s)"],
      "a call on a negative literal" => ["-((-1).to_s)", "--1.to_s"],
      "a longer chain" => ["-(1.abs.to_s)", "-(1.abs.to_s)"],
      "a safe navigation" => ["-(1&.abs)", "-(1&.abs)"],
      "an index" => ["-(1.abs[0])", "-(1.abs[0])"],
      "a block" => ["-(1.then {})", "-(1.then {\n})"],
      "a numbered block" => ["-(1.then { _1 })", "-(1.then {\n  _1\n})"],
      "an it block" => ["-(1.then { it })", "-(1.then {\n  it\n})"],
      "a power" => ["-(2 ** 2)", "-(2 ** 2)"]
    }.each do |shape, (source, written)|
      it "writes minus over #{shape} rooted at a literal so the sign stays the call's" do
        expect(write(unparenthesized(source))).to(eq(written))
      end
    end

    it "writes plus over a chain rooted at a literal with the chain in parentheses" do
      expect(write(unparenthesized("+(1.abs)"))).to(eq("+(1.abs)"))
    end

    it "writes a sign over a signed chain with only the chain in parentheses" do
      expect(write(unparenthesized("-(-(1.abs))"))).to(eq("--(1.abs)"))
    end

    it "writes other signs, and other operands, as they read" do
      sources = ["~(1.abs)", "!(1.abs)", "-(1)", "+(1)", "-[1]", "1.abs&.-@"]
      expect(
        sources.map do |source|
          write(unparenthesized(source))
        end
      ).to(eq(["~1.abs", "!1.abs", "-1", "+1", "-[1]", "1.abs&.-@"]))
    end

    it "re-emits a negated call and a parenthesized literal as written" do
      expect([reemit("-a.abs"), reemit("-(1)")]).to(eq(["-a.abs", "-(1)"]))
    end

    {
      "an integer" => "(-1) ** 2", "a float" => "(-0.0) ** 2",
      "a rational" => "(-1r) ** 2", "an imaginary" => "(-1i) ** 2"
    }.each do |kind, written|
      it "writes #{kind} negative literal raised to a power in parentheses" do
        expect(write(unparenthesized(written))).to(eq(written))
      end
    end

    it "writes other bases and operators as they read", :aggregate_failures do
      expect(write(unparenthesized("2 ** -1"))).to(eq("2 ** -1"))
      expect(write(unparenthesized("-1 * 2"))).to(eq("-1 * 2"))
      expect(write(unparenthesized("((-1).abs) ** 2"))).to(eq("-1.abs ** 2"))
      expect(write(unparenthesized("\"-a\" ** 2"))).to(eq("\"-a\" ** 2"))
      expect(reemit("10 ** 3")).to(eq("10 ** 3"))
    end

    # What Ruby itself reads back, not only the text.
    it "writes code that evaluates like the tree", :aggregate_failures do
      expect(Object.new.instance_eval(write(unparenthesized("-(1.to_s)")))).to(eq("1"))
      expect(Object.new.instance_eval(write(unparenthesized("(-1) ** 2")))).to(eq(1))
    end

    {
      "minus over a chain" => ["\"x\#{-(1.abs)}\"", "x-1"],
      "a negative literal raised to a power" => ["\"x\#{(-2) ** 2}\"", "x4"]
    }.each do |shape, (written, value)|
      it "writes #{shape} inside an interpolation", :aggregate_failures do
        expect(write(unparenthesized(written))).to(eq(written))
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
      "statements in one interpolation" => [statement("\"\#{1; 2}\""), "\"\#{1; 2}\"", "2"],
      "an if node straight in a string" => [
        interpolated(plain("a"), branched(statement("true"), statement('"b"'), statement('"c"'))),
        "\"a\#{if true\n  \"b\"\nelse\n  \"c\"\nend}\"", "ab"
      ],
      "a string in a string" => [
        interpolated(plain("a"), interpolated(plain("b"), embedded("1"))), "\"a\" \"b\#{1}\"", "ab1"
      ],
      "adjacent plain parts" => [interpolated(plain("a"), plain("b"), embedded("1")), "\"ab\#{1}\"", "ab1"],
      "an empty part" => [interpolated(plain(""), embedded("1"), plain("")), "\"\#{1}\"", "1"],
      "a lone part" => [interpolated(plain("a")), "\"a\"", "a"],
      "no parts" => [interpolated, "\"\"", ""],
      "a variable read straight" => [interpolated(statement('"#@a"').parts.first, plain("b")), "\"\#{@a}b\"", "b"],
      "a variable read before a stop" => [interpolated(statement('"#@a"').parts.first, plain(".")), "\"\#@a.\"", "."],
      "a hash sign before an interpolation" => [interpolated(plain("#"), embedded("1")), "\"#\#{1}\"", "#1"],
      "a hash sign before a brace" => [interpolated(plain("#"), plain("{a}")), "\"\\\#{a}\"", "\#{a}"]
    }.each do |shape, (node, written, value)|
      it "writes #{shape}", :aggregate_failures do
        expect(write(node)).to(eq(written))
        expect(evaluates(node)).to(eq(value))
      end
    end

    it "writes a heredoc as one string of its lines" do
      source = "x = <<~TEXT\n  a\n  b \#{c}\nTEXT\n"
      expect([reemit(source), shape(parse(reemit(source)))]).to(eq(["x = \"a\\nb \#{c}\\n\"", shape(parse(source))]))
    end

    it "keeps juxtaposed strings juxtaposed" do
      expect(reemit("\"a\" \"b\#{c}\" 'd'")).to(eq("\"a\" \"b\#{c}\" \"d\""))
    end

    # Merging a multi-line %r{}x's str parts left no delimiter unparser could
    # emit, which sank the whole file (mastodon lost 107 mutants to it).
    [
      "%r{\n  a/b   # a comment\n  \#{c}\n}x", "%r{a/b}", "/a\\/b/", "%r{a\\}b}", "%r[a/{b}]"
    ].each do |source|
      it "writes `#{source}` with the delimiters it was written with" do
        expect(reemit(source)).to(eq(source))
      end
    end

    it "builds a pattern with a delimiter it does not use, and escapes slashes when it uses every one",
      :aggregate_failures do
      expect(write(pattern("a/b", "i"))).to(eq("%r{a/b}i"))
      expect(write(pattern("/{[(<|!", "i"))).to(eq("/\\/{[(<|!/i"))
      expect(pattern("/{[(<|!", "").unescaped).to(eq("/{[(<|!"))
    end
  end

  # unparser wrote a guard after `return` as a keyword `if`, which Ruby reads
  # as a modifier, and `a || b and c` for a mutated chain.
  describe "keywords that read differently where they sit" do
    it "writes a condition after return as a ternary" do
      expect(write(bare(statement("return (if a then 1 end)")))).to(eq("return a ? 1 : nil"))
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
      expect(write(bare(statement("(a && (b = 1)) || c")))).to(eq("a && (b = 1) || c"))
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
        "foo\nfoo()\nFoo()\na.foo\nfoo(1, 2)\n",
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
        "foo { |x|\n  a rescue b\n}",
      "foo do |x|\n  a\nrescue\n  b\nend" =>
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
        "unless a\n  b\nelse\n  c\nend",
      "if a; else; c; end" =>
        "if a\nelse\n  c\nend",
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
      "loop { next; break 1 }; return 1, 2" =>
        "loop {\n  next\n  break 1\n}\nreturn 1, 2\n",
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
      "x = { frozen?: frozen? }" =>
        "x = { frozen?: frozen? }",
      "x = \"\\r\\n\" \"\\r\\n\#{y}\\r\\n\" \"z\"" =>
        "x = \"\\r\\n\" \"\\r\\n\#{y}\\r\\n\" \"z\"",
      "x = \"a\\r\\nb\#{c}\"" =>
        "x = \"a\\r\\nb\#{c}\"",
      "begin; end" =>
        "begin\nend",
      "return x rescue y" =>
        "return x rescue y",
      "loop { a = b || next }" =>
        "loop {\n  a = b || next\n}",
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
      "def m; yield; yield(a); super; super(); super(a); defined?(a); end" =>
        "def m\n  yield\n  yield(a)\n  super\n  super()\n  super(a)\n  defined?(a)\nend",
      "x = (a and b)" =>
        "x = (a and b)",
      "a && (not b)" =>
        "a && (not b)",
      "x = (b = 1 if b)" =>
        "x = (b = 1 if b)",
      "x = <<~A\n  a\n    b\nA" =>
        "x = \"a\\n  b\\n\"",
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
        "\"\#{}\"",
      "a = [a]; b ||= [b]" =>
        "a = [a]\nb ||= [b]\n",
      "class A < (b = B); end; b" =>
        "class A < (b = B)\nend\nb\n",
      "x { |; a| }" =>
        "x { |; a|\n}",
      "a[1] { }" =>
        "a[1] {\n}",
      "begin; rescue => a&.b; end" =>
        "begin\nrescue => a&.b\nend",
      "x = ()" =>
        "x = ()",
      "not a = 1" =>
        "not a = 1",
      "if (def m(d) = d); d = 1; end" =>
        "if (def m(d)\n  d\nend)\n  d = 1\nend",
      "case v; in (B => _x) | A then 1; end" =>
        "case v\nin (B => _x) | A\n  1\nend"
    }.each do |source, written|
      it "writes `#{source}` as `#{written}`", :aggregate_failures do
        expect(reemit(source)).to(eq(written))
        expect(shape(parse(written))).to(eq(shape(parse(source))))
      end
    end
  end

  # Trees no source reads as, written as Ruby reads them back.
  describe "trees a mutation can leave" do
    def self.unparenthesized(source) = bare(statement(source))

    # A method body that holds a clause, as a guard moves it into a branch.
    def self.clause(body) = statement("def m\n#{body}\nend").body

    def self.assigned(value) = statement("x = a").copy(value: value)

    def self.argued(node)
      statement("f(a)").then { |call| call.copy(arguments: call.arguments.copy(arguments: [node])) }
    end

    def self.alternative
      arm = statement("case v; in B | A then 1; end").then { |match| [match, match.conditions.first] }
      capture = statement("case v; in B => _x then 1; end").conditions.first.pattern
      arm.first.copy(conditions: [arm.last.copy(pattern: arm.last.pattern.copy(left: capture))])
    end

    def self.followed(modifier, node) = modifier.copy(statements: statements([*modifier.statements.body, node]))

    def self.infinite(literal) = literal.copy(value: literal.value.positive? ? Float::INFINITY : -Float::INFINITY)

    {
      "no parts" => [interpolated, "\"\""],
      "an escaped hash sign before a brace" => [
        interpolated(plain("#"), plain("{a}"), embedded("1")),
        "\"\\\#{a}\#{1}\""
      ],
      "an interpolation beside a nested string" => [
        interpolated(interpolated(plain("a"), embedded("1")), embedded("2")), "\"a\#{1}\" \"\#{2}\""
      ],
      "a line ending in a carriage return and a newline" => [
        interpolated(plain("a\r\n"), plain("b"), embedded("c")), "\"a\\r\\nb\#{c}\""
      ],
      "an assignment rescued as a modifier" => [unparenthesized("(x = a) rescue b"), "(x = a) rescue b"],
      "a setter with no receiver" => [statement("self.a = 1").copy(receiver: nil), "self.a = 1"],
      "a loop after return" => [unparenthesized("return (while a do b end)"), "return (while a\n  b\nend)"],
      "or over a bare jump, built with no source" => [
        statement("a || b").copy(right: statement("return")),
        "a || return"
      ],
      "or over a jump with a value, built with no source" => [
        statement("a || b").copy(right: statement("return 1")), "a or return 1"
      ],
      "and with not on its right" => [unparenthesized("a && (not b)"), "a && (not b)"],
      "and as a value" => [unparenthesized("x = (a and b)"), "x = (a and b)"],
      "a modifier as a value" => [unparenthesized("x = (b = 1 if b)"), "x = (b = 1 if b)"],
      "not over a connective" => [unparenthesized("not (a and b)"), "not(a and b)"],
      "a ternary with no middle" => [unparenthesized("return (if a then else b end)"), "return a ? nil : b"],
      "a ternary with a condition in the middle" => [
        unparenthesized("return (if a then (if b then c else d end) else e end)"),
        "return a ? (if b\n  c\nelse\n  d\nend) : e"
      ],
      "a condition before an operator" => [
        unparenthesized("(if a then b else c end) || d"),
        "if a\n  b\nelse\n  c\nend || d"
      ],
      "a condition after an operator" => [
        unparenthesized("d || (if a then b else c end)"),
        "d || if a\n  b\nelse\n  c\nend"
      ],
      "a condition as a receiver" => [unparenthesized("(if a then b else c end).d"), "if a\n  b\nelse\n  c\nend.d"],
      "a rescue modifier as an argument" => [
        bare(statement("def m = yield((a rescue b))").body.body.first),
        "yield((a rescue b))"
      ],
      "a constant valued pair" => [statement("{ A: A }"), "{ A: A }"],
      "not a number" => [statement("1.5").copy(value: Float::NAN), "Float::NAN"],
      "infinity" => [
        statement("[1.5, -1.5]").then { |list| list.copy(elements: list.elements.map { |item| infinite(item) }) },
        "[Float::INFINITY, -Float::INFINITY]"
      ],
      "a rational with no decimal" => [statement("1r").copy(numerator: 1, denominator: 3), "Rational(1, 3)"],
      "a rational with a decimal" => [statement("1r").copy(numerator: 5, denominator: 2), "2.5r"],
      "a string with bytes beside a character" => [
        statement('"a"').copy(unescaped: (+"é\xFF").force_encoding(Encoding::UTF_8)), "\"\\xC3\\xA9\\xFF\""
      ],
      "a binary string" => [statement('"a"').copy(unescaped: "é".b), "\"\\xC3\\xA9\""],
      "a loop that runs its body first, as a value" => [
        unparenthesized("x = (begin; a; end while b)"), "x = (begin\n  a\nend while b)"
      ],
      "a rescue of nothing, as a value" => [assigned(clause("rescue\n  b")), "x = begin\nrescue\n  b\nend"],
      "a rescue with two handlers, as a value" => [
        assigned(clause("a\nrescue A\n  b\nrescue\n  c")), "x = begin\n  a\nrescue A\n  b\nrescue\n  c\nend"
      ],
      "a rescue with an else, as a value" => [
        assigned(clause("a\nrescue\n  b\nelse\n  c")), "x = begin\n  a\nrescue\n  b\nelse\n  c\nend"
      ],
      "a rescue of a class, as a value" => [
        assigned(clause("a\nrescue A\n  b")),
        "x = begin\n  a\nrescue A\n  b\nend"
      ],
      "a rescue binding the error, as a value" => [
        assigned(clause("a\nrescue => e\n  b")), "x = begin\n  a\nrescue => e\n  b\nend"
      ],
      "a rescue of a class, as an argument" => [
        statement("f(a)").then do |call|
          call.copy(arguments: call.arguments.copy(arguments: [clause("a\nrescue A\n  b")]))
        end,
        "f(begin\n  a\nrescue A\n  b\nend)"
      ],
      "an ensure, as a value" => [assigned(clause("a\nensure\n  b")), "x = begin\n  a\nensure\n  b\nend"],
      "a sequence as an argument" => [argued(statements([named(:a), named(:b)])), "f((a; b))"],
      "a sequence inside a sequence" => [statements([named(:a), statements([named(:b), named(:c)])]), "a\nb\nc\n"],
      "an elsif as a ternary branch" => [
        unparenthesized("return (if a then b elsif c then d else e end)"),
        "return a ? b : (if c\n  d\nelse\n  e\nend)"
      ],
      "statements as a ternary branch" => [
        unparenthesized("return (if a then b; c else d end)"),
        "return a ? (b; c) : d"
      ],
      "a lone statement as an argument" => [argued(statements([named(:a)])), "f(a)"],
      "a modifier over statements" => [followed(statement("d = 1 if d"), named(:e)), "(d = 1; e) if d"],
      "a capture on the left of an alternative" => [alternative, "case v\nin (B => _x) | A\n  1\nend"],
      "a singleton method on a call" => [
        statement("def a.m; end").copy(receiver: statement("a.b")),
        "def (a.b).m\nend"
      ],
      "not over a condition" => [
        statement("not x").copy(receiver: branched(named(:a), named(:b), named(:c))), "not(if a\n  b\nelse\n  c\nend)"
      ]
    }.each do |shape, (tree, written)|
      it "writes #{shape}" do
        expect(write(tree)).to(eq(written))
      end
    end

    # Only a modifier reads what its body binds, and a modifier takes no else.
    it "refuses a condition reading what its body binds once an else follows" do
      tree = statement("d = 1 if d").copy(subsequent: statement("if a then b else c end").subsequent)
      expect { write(tree) }.to(raise_error(described_class::Unbound, /read of d/))
    end

    it "writes a shareable constant as its assignment" do
      expect(reemit("# shareable_constant_value: literal\nA = [1]")).to(eq("A = [1]"))
    end

    it "writes a complex number with a real part as its constructor" do
      expect(Kimera::Scribe::Number.new(Complex(1, 2)).text).to(eq("Complex(1, 2)"))
    end

    it "writes nothing for no tree" do
      expect(write(nil)).to(eq(""))
    end

    it "refuses a node type it does not know" do
      unknown = Data.define(:type) { def compact_child_nodes = [] }.new(:unknown_node)
      expect { write(unknown) }.to(raise_error(ArgumentError, "kimera cannot write a unknown_node"))
    end
  end

  # R6B4-M1: a guard ending in an endless range ran on into the next line:
  # `when 90.. then "A"` was written `when 90..` / `"A"`, which Ruby reads as
  # `when 90.."A"` (a bad value for range); `if x..; y; end` read `if x..y`.
  describe "a condition ending in an endless range" do
    {
      "case v; when 3.. then :big; end" => "case v\nwhen 3..;\n  :big\nend",
      "case v; when 1, 3..; :big; end" => "case v\nwhen 1, 3..;\n  :big\nend",
      "case v; in 3.. then :big; end" => "case v\nin 3..;\n  :big\nend",
      "case 1; in ..3 | 5..; end" => "case 1\nin ..3 | 5..;\nend",
      "if x..; y; end" => "if x..;\n  y\nend", "if x...; end" => "if x...;\nend",
      "if a; elsif x..; y; end" => "if a\nelsif x..;\n  y\nend", "unless x..; y; end" => "unless x..;\n  y\nend",
      "while x..; y; end" => "while x..;\n  y\nend", "until x..; end" => "until x..;\nend",
      "for a in 1..; b; end" => "for a in 1..;\n  b\nend", ":big if v in 3.." => "if v in 3..;\n  :big\nend"
    }.each do |source, written|
      it "ends `#{source}`'s guard before the line break", :aggregate_failures do
        expect(reemit(source)).to(eq(written))
        expect(shape(parse(written))).to(eq(shape(parse(source))))
      end
    end

    it "writes it on one line as it reads" do
      joined = described_class.new(parse("case v; when 3..; :big; end")).joined
      expect(joined.text).to(eq("case v; when 3..;; :big; end"))
    end
  end

  # R6B4-M2: a %w/%i literal in a pattern is a value (`%w[a b] === value`);
  # written as `["a", "b"]` it read as an array pattern, which a Struct of
  # "a" and "b" matches.
  describe "a word list in a pattern" do
    {
      "case v; in %w[a b] then :pair; end" => "case v\nin %W[a b]\n  :pair\nend", "x in %i[a b]" => "x in %I[a b]",
      "x => %w[]" => "x => %w[]", "x in [%w[a], 1]" => "x in [%W[a], 1]", "x in {k: %i[a]}" => "x in { k: %I[a] }",
      "x in %w[a] | %i[b]" => "x in %W[a] | %I[b]", "x in %w[a] => y" => "x in %W[a] => y",
      "x in [*, %w[a], *]" => "x in [*, %W[a], *]", "x in Foo[%w[a]]" => "x in Foo(%W[a])",
      "x in %W[a \#{b} c\#{d}e]" => "x in %W[a \#{b} c\#{d}e]", "x in %I[a \#{b}]" => "x in %I[a \#{b}]",
      "x in %w[a\\ b c\\]d \\[ \#{]" => "x in %W[a\\ b c\\]d \\[ \\\#{]",
      "x in %W[\\u3042 \\n]" => "x in %W[\\u{3042} \\n]",
      "case v; in %w[a] if [1].any?; end" => "case v\nin %W[a] if [1].any?\nend",
      "x in ^(%w[a])" => "x in ^([\"a\"])", "x in ->(y) { y == [1] }" => "x in ->(y) {\n  y == [1]\n}",
      "x = %w[a b]" => "x = [\"a\", \"b\"]"
    }.each do |source, written|
      it "writes `#{source}` as `#{written}`", :aggregate_failures do
        expect(reemit(source)).to(eq(written))
        expect(shape(parse(written))).to(eq(shape(parse(source))))
      end
    end

    def self.listed(*elements) = statement("x in %w[a]").then { it.copy(pattern: it.pattern.copy(elements: elements)) }

    {
      "an empty word" => [listed(plain(""), plain("b")), "x in ^([\"\", \"b\"])"],
      "a string beside a symbol" => [listed(plain("a"), statement(":b")), "x in ^([\"a\", :b])"],
      "a number" => [listed(statement("1")), "x in ^([1])"]
    }.each do |kind, (tree, written)|
      it "pins a word list with #{kind}, which no %-literal can hold" do
        expect(write(tree)).to(eq(written))
      end
    end
  end

  # Every file of kimera's own reads back as the very tree it was written from.
  it "writes kimera's own sources so they read back as the same tree", :aggregate_failures do
    Dir[File.expand_path("../../lib/**/*.rb", __dir__)].each do |file|
      tree = parse(File.read(file, encoding: Encoding::UTF_8))
      expect(shape(parse(write(tree)))).to(eq(shape(tree)), file)
    end
  end
end
