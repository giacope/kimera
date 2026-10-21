# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/synthesis/overlay"

RSpec.describe(Kimera::Operators) do
  def scan(code, *keys)
    Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: keys)).source(code, file: "r.rb")
  end

  def patterns(code, *keys)
    scan(code, *keys).each.map { |m, p| Kimera::Rewrite::Directive.new(m.directive).render(p.original_source) }
  end

  def tokens(source) = Kimera::Operators::RegexpTokens.new(source).tokens.map { [it.kind, it.text] }

  describe Kimera::Operators::RegexpTokens do
    it "finds anchors and quantifiers with their modifiers", :aggregate_failures do
      expect(tokens('\A\d+?\z')).to(eq([[:anchor, '\A'], [:quantifier, "+?"], [:anchor, '\z']]))
      expect(tokens("^a*+b{2,3}c{,4}d{1,}e{2}$"))
        .to(
          eq(
            [
              [:anchor, "^"], [:quantifier, "*+"], [:quantifier, "{2,3}"], [:quantifier, "{,4}"],
              [:quantifier, "{1,}"], [:quantifier, "{2}"], [:anchor, "$"]
            ]
          )
        )
    end

    it "skips what only looks like one: classes, escapes, group openers, literal braces", :aggregate_failures do
      expect(tokens('[]^$+*?]x\+\$\\\\')).to(eq([]))
      expect(tokens("[a[^b]]+")).to(eq([[:quantifier, "+"]]))
      expect(tokens("(?<name>a)(?:b)(?=c)(?<!d)(?i)(?#e+)f")).to(eq([]))
      expect(tokens('\p{Alpha}\k<name>\u{41}x{a}y{')).to(eq([]))
      expect(tokens("+a")).to(eq([]))
      expect(tokens("(?:ab)?")).to(eq([[:quantifier, "?"]]))
      expect(tokens("(a)+")).to(eq([[:quantifier, "+"]]))
    end

    it "takes a quantifier only after something it can repeat", :aggregate_failures do
      expect(tokens("(+")).to(eq([]))
      expect(tokens("(?i)+")).to(eq([]))
      expect(tokens("^*")).to(eq([[:anchor, "^"]]))
      expect(tokens('\p{L}+')).to(eq([[:quantifier, "+"]]))
    end

    it "ends a character class only at its own closing bracket", :aggregate_failures do
      expect(tokens('[\]$]')).to(eq([]))
      expect(tokens("[^]$]")).to(eq([]))
      expect(tokens("[a]$")).to(eq([[:anchor, "$"]]))
      expect(tokens("[a")).to(eq([]))
    end
  end

  it "drops each anchor, down to an empty pattern", :aggregate_failures do
    expect(patterns('def m(s) = s.match?(/\A\d+$/i)', "regexp_anchor")).to(eq(['/\d+$/i', '/\A\d+/i']))
    expect(patterns("def m(s) = s =~ /^/", "regexp_anchor")).to(eq(["//"]))
  end

  it "swaps + and *, drops ?, and loosens each bound by one", :aggregate_failures do
    expect(patterns('def m(s) = s =~ /a+b*?c?\d{2,3}e{2}/', "regexp_quantifier"))
      .to(
        eq(
          [
            '/a*b*?c?\d{2,3}e{2}/', '/a+b+?c?\d{2,3}e{2}/', '/a+b*?c\d{2,3}e{2}/',
            '/a+b*?c?\d{1,3}e{2}/', '/a+b*?c?\d{2,4}e{2}/', '/a+b*?c?\d{2,3}e{1}/', '/a+b*?c?\d{2,3}e{3}/'
          ]
        )
      )
    expect(patterns("def m(s) = s =~ /x{1}y{0,2}z{3,}/", "regexp_quantifier"))
      .to(eq(["/x{2}y{0,2}z{3,}/", "/x{1}y{0,3}z{3,}/", "/x{1}y{0,2}z{2,}/"]))
  end

  it "leaves interpolated, extended, and differently escaped patterns alone" do
    code = "def m(s, x)\n  s =~ /\#{x}+/\n  s =~ /a+ # one or more/x\n  s =~ %r!a\\!+!\nend\n"
    expect(scan(code, "regexp_anchor", "regexp_quantifier").each.count).to(eq(0))
  end

  it "keeps the flags and a slash in the pattern", :aggregate_failures do
    expect(patterns('def m(s) = s.match?(%r{\Aa/b+}i)', "regexp_quantifier")).to(eq(['%r{\Aa/b*}i']))
    expect(patterns('def m(s) = s.match?(/\A\/x/)', "regexp_anchor")).to(eq(["%r{/x}"]))
  end

  it "matches as the mutant does once flipped", :aggregate_failures do
    stub_const("RegexpOps", Class.new)
    code = "class RegexpOps\n  def code?(s) = s.match?(/\\A[A-Z]{3}\\z/)\nend\n"
    catalog = scan(code, "regexp_anchor", "regexp_quantifier")
    Kimera::Overlay::Source.new(Kimera::Overlay.new(catalog).synthesize("r.rb", code).source).evaluate("r.rb")
    ids = catalog.each.to_h { |m, _p| [m.label, m.id] }
    expect(RegexpOps.new.code?("xABC")).to(be(false))
    Kimera::RUNTIME.active = ids.fetch('regexp: drop `\A`')
    expect(RegexpOps.new.code?("xABC")).to(be(true))
    Kimera::RUNTIME.active = ids.fetch("regexp: `{3}` => `{2}`")
    expect(RegexpOps.new.code?("AB")).to(be(true))
  ensure
    Kimera::RUNTIME.reset!
  end
end
