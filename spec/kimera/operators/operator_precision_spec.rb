# frozen_string_literal: true

require "kimera/operators"
require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/synthesis/overlay"

RSpec.describe("operator precision") do
  def mutants(src, key, file: "p.rb")
    catalog = Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: [key])).source(src, file: file)
    catalog.each.map { |m, _p| m }
  end

  def only(src, key)
    ms = mutants(src, key)
    expect(ms.size).to(eq(1), "expected exactly one mutant, got #{ms.map(&:label)}")
    ms.first
  end

  describe "numeric_literal floats (never covered by the integer fixture)" do
    it "shifts a float by +1.0 with the exact label and full directive", :aggregate_failures do
      m = only("def rate\n  2.5\nend\n", "numeric_literal")
      expect(m.label).to(eq("2.5 => 3.5"))
      expect(m.directive).to(eq("type" => "float_literal", "value" => 3.5))
    end

    it "flips the float live through an overlay", :aggregate_failures do
      src = "def rate\n  2.5\nend\n"
      catalog = Kimera::RegistryScan.new(
        operators: Kimera::Operators.build(keys: ["numeric_literal"])
      ).source(src, file: "p.rb")
      result = Kimera::Overlay.new(catalog).synthesize("p.rb", src)
      mod = Module.new.tap { |m| m.module_eval(result.source) }
      object = Object.new.extend(mod)
      Kimera::Runtime.active = nil
      expect(object.rate).to(eq(2.5))
      Kimera::Runtime.active = catalog.each.first.first.id
      expect(object.rate).to(eq(3.5))
    ensure
      Kimera::Runtime.reset!
    end
  end

  describe "integer_literal full directive" do
    it "carries the exact integer target in each directive", :aggregate_failures do
      ms = mutants("def n\n  5\nend\n", "numeric_literal")
      table = ms.to_h { |m| [m.label, m.directive] }
      expect(table["5 => 4"]).to(eq("type" => "integer_literal", "value" => 4))
      expect(table["5 => 6"]).to(eq("type" => "integer_literal", "value" => 6))
      expect(table["5 => 0"]).to(eq("type" => "integer_literal", "value" => 0))
    end

    it "does not append a redundant zero target for a literal zero" do
      labels = mutants("def z\n  0\nend\n", "numeric_literal").map(&:label)
      expect(labels).to(contain_exactly("0 => -1", "0 => 1"))
    end

    # For 1, the off-by-one `1 => 0` duplicates the explicit zero target.
    it "dedups the off-by-one that collides with the explicit zero" do
      labels = mutants("def one\n  1\nend\n", "numeric_literal").map(&:label)
      expect(labels).to(contain_exactly("1 => 0", "1 => 2"))
    end
  end

  describe "range exclusivity (the exclude_end? branch)" do
    it "flips an inclusive range to exclusive with exact label and directive", :aggregate_failures do
      m = only("def s\n  (2..5)\nend\n", "range")
      expect(m.label).to(eq(".. => ..."))
      expect(m.directive).to(eq("type" => "range_flip", "to" => "erange"))
    end

    it "flips an exclusive range to inclusive (the uncovered arm)", :aggregate_failures do
      m = only("def s\n  (2...5)\nend\n", "range")
      expect(m.label).to(eq("... => .."))
      expect(m.directive).to(eq("type" => "range_flip", "to" => "irange"))
    end

    it "makes an exclusive range inclusive live through an overlay", :aggregate_failures do
      src = "def s\n  (2...5)\nend\n"
      catalog = Kimera::RegistryScan.new(
        operators: Kimera::Operators.build(keys: ["range"])
      ).source(src, file: "p.rb")
      result = Kimera::Overlay.new(catalog).synthesize("p.rb", src)
      mod = Module.new.tap { |m| m.module_eval(result.source) }
      object = Object.new.extend(mod)
      Kimera::Runtime.active = nil
      expect(object.s.to_a).to(eq([2, 3, 4]))
      Kimera::Runtime.active = catalog.each.first.first.id
      expect(object.s.to_a).to(eq([2, 3, 4, 5]))
    ensure
      Kimera::Runtime.reset!
    end
  end

  describe "collection_literal hash (the hash arm and its directive)" do
    it "empties a hash literal with the exact label and directive", :aggregate_failures do
      m = only("def h\n  { a: 1 }\nend\n", "collection_literal")
      expect(m.label).to(eq("hash => {}"))
      expect(m.directive).to(eq("type" => "empty_collection"))
    end

    it "empties an array literal with the exact label and directive", :aggregate_failures do
      m = only("def a\n  [1, 2]\nend\n", "collection_literal")
      expect(m.label).to(eq("array => []"))
      expect(m.directive).to(eq("type" => "empty_collection"))
    end
  end

  describe "boolean_literal full directives" do
    it "carries the exact target in the true and false directives", :aggregate_failures do
      t = only("def y\n  true\nend\n", "boolean_literal")
      expect(t.label).to(eq("true => false"))
      expect(t.directive).to(eq("type" => "boolean_literal", "to" => "false"))

      f = only("def n\n  false\nend\n", "boolean_literal")
      expect(f.label).to(eq("false => true"))
      expect(f.directive).to(eq("type" => "boolean_literal", "to" => "true"))
    end
  end

  describe "boolean_connective full directives" do
    it "carries the exact connective target", :aggregate_failures do
      a = only("def m(x, y)\n  x && y\nend\n", "boolean_connective")
      expect(a.label).to(eq("&& => ||"))
      expect(a.directive).to(eq("type" => "boolean_connective", "to" => "or"))

      o = only("def m(x, y)\n  x || y\nend\n", "boolean_connective")
      expect(o.label).to(eq("|| => &&"))
      expect(o.directive).to(eq("type" => "boolean_connective", "to" => "and"))
    end
  end

  describe "regexp_literal directives (match-all and match-none extremes)" do
    it "carries the exact source for each extreme", :aggregate_failures do
      table = mutants("def re\n  /ab+/\nend\n", "regexp").to_h { |m| [m.label, m.directive] }
      expect(table["regexp => // (match all)"]).to(eq("type" => "regexp_literal", "source" => ""))
      expect(table["regexp => /(?!)/ (match none)"]).to(eq("type" => "regexp_literal", "source" => "(?!)"))
    end

    it "flips a regexp to match-none live through an overlay", :aggregate_failures do
      src = "def re(s)\n  s.match?(/ab+/)\nend\n"
      catalog = Kimera::RegistryScan.new(
        operators: Kimera::Operators.build(keys: ["regexp"])
      ).source(src, file: "p.rb")
      result = Kimera::Overlay.new(catalog).synthesize("p.rb", src)
      mod = Module.new.tap { |m| m.module_eval(result.source) }
      object = Object.new.extend(mod)
      Kimera::Runtime.active = nil
      expect(object.re("abb")).to(be(true))
      none = catalog.each.find { |m, _p| m.label.include?("match none") }.first
      Kimera::Runtime.active = none.id
      expect(object.re("abb")).to(be(false))
    ensure
      Kimera::Runtime.reset!
    end
  end

  describe "string_literal label truncation" do
    it "truncates the label to 30 characters of the inspected value", :aggregate_failures do
      long = "x" * 50
      m = only("def s\n  \"#{long}\"\nend\n", "string_literal")
      inspected = long.inspect[0, 30]
      expect(m.label).to(eq("#{inspected} => \"\""))
      expect(m.directive).to(eq("type" => "string_literal", "value" => ""))
    end
  end

  # Pins the `node.arguments&.` safe navigation; `.` would raise on nil.
  describe "rails matchers tolerate argument-less DSL calls" do
    def build(src, key)
      Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: [key])).source(src, file: "app.rb")
    end

    it "rails_permit: a bare permit yields no mutant and does not raise", :aggregate_failures do
      catalog = nil
      expect { catalog = build("def m\n  params.permit\nend\n", "rails_permit") }
        .not_to(raise_error)
      expect(catalog.each.count).to(eq(0))
    end

    it "rails_association: an argument-less has_many yields no mutant and does not raise", :aggregate_failures do
      catalog = nil
      expect { catalog = build("class Foo\n  has_many\nend\n", "rails_association") }
        .not_to(raise_error)
      expect(catalog.each.count).to(eq(0))
    end

    it "rails_callback: an argument-less before_action still deletes cleanly", :aggregate_failures do
      catalog = nil
      expect { catalog = build("class Foo\n  before_action\nend\n", "rails_callback") }
        .not_to(raise_error)
      # Deletion is unconditional; the scope-drop path finds no kwargs.
      expect(catalog.each.map { |m, _p| m.label }).to(eq(["delete `before_action`"]))
    end
  end

  describe "rails_association keys on dependent: specifically" do
    def assocs(src)
      Kimera::RegistryScan.new(operators: Kimera::Operators.build(keys: ["rails_association"]))
        .source(src, file: "app.rb").each.to_a
    end

    it "emits a drop only for a real dependent: option", :aggregate_failures do
      ms = assocs("class Foo\n  has_many :posts, dependent: :destroy\nend\n")
      expect(ms.map { |m, _p| m.label }).to(eq(["has_many :posts, dependent: :destroy: drop dependent:"]))
    end

    it "ignores a non-dependent symbol-keyed option (kills the &&=>|| guard)" do
      ms = assocs("class Foo\n  has_many :posts, class_name: \"P\"\nend\n")
      expect(ms).to(be_empty)
    end

    it "labels a multi-line association with its stripped first line" do
      src = <<~RUBY
        class Foo
          has_many :posts,
                   dependent: :destroy
        end
      RUBY
      ms = assocs(src)
      expect(ms.map { |m, _p| m.label }).to(eq(["has_many :posts,: drop dependent:"]))
    end
  end

  # Dropping either of two equal neighbors leaves the same program.
  describe "drops of equal neighbors" do
    def indexes(src, key) = mutants(src, key).map { |m| m.directive["index"] }

    it "keeps one drop per run of equal neighbors", :aggregate_failures do
      expect(indexes("def m\n  [7, 7]\nend\n", "element_drop")).to(eq([0]))
      expect(indexes("def m\n  f(1, 1, 2)\nend\n", "argument_drop")).to(eq([0, 2]))
      expect(indexes("def m\n  [7, 8, 7]\nend\n", "element_drop")).to(eq([0, 1, 2]))
    end

    def kept(elements) = indexes("def m(a)\n  [#{elements}]\nend\n", "element_drop")

    # `-(1)` and `-1` are one value: dropping either leaves the same program.
    it "counts neighbors equal up to parentheses and a negated literal as equal", :aggregate_failures do
      expect(indexes("def m\n  [-(1), -1].include?(1)\nend\n", "element_drop")).to(eq([0]))
      expect(indexes("def m\n  f(-(1), -1)\nend\n", "argument_drop")).to(eq([0]))
      expect(kept("(a), a, ((a))")).to(eq([0]))
      expect(kept("-(-1), 1, (1)")).to(eq([0]))
      expect(kept("-(1.5), -1.5, -(1r), -1r, -(2i), -2i")).to(eq([0, 2, 4]))
      expect(kept("[-(1)].first, [-1].first, -a, -(a), a.-@")).to(eq([0, 2]))
    end

    it "still tells apart neighbors that differ", :aggregate_failures do
      expect(kept("-(1), 1, 0.0, -(0.0), 1.0")).to(eq([0, 1, 2, 3, 4]))
      expect(kept("(1; 2), 1, 1.-@(2), -1, 1.-@ { }, -1")).to(eq([0, 1, 2, 3, 4, 5]))
      expect(kept("a&.b, a.b, a.+(1), a.-(1), a.-@(1), -a")).to(eq([0, 1, 2, 3, 4, 5]))
      expect(kept("+(1), -1, (), nil, [1], [2]")).to(eq([0, 1, 2, 3, 4, 5]))
    end

    it "tells heredocs with the same opener apart by their bodies" do
      expect(indexes("def m\n  f(<<~A, <<~A)\n    x\n  A\n    y\n  A\nend\n", "argument_drop")).to(eq([0, 1]))
    end
  end

  # Forcing `if true` to true leaves it unchanged: a survivor no test can kill.
  describe "conditional on a literal condition" do
    def labels(src) = mutants(src, "conditional").map(&:label)

    it "only forces a literal condition to the other literal", :aggregate_failures do
      expect(labels("def m(a)\n  a if true\nend\n")).to(eq(["condition => false"]))
      expect(labels("def m(a)\n  a unless false\nend\n")).to(eq(["condition => true"]))
      expect(labels("def m(a)\n  a if a\nend\n")).to(eq(["condition => true", "condition => false"]))
    end
  end

  describe "argument_drop label slicing (multi-line / padded)" do
    it "labels a multi-line argument with its stripped first line", :aggregate_failures do
      src = "def m\n  helper(build(\n    :deep\n  ), other)\nend\n"
      labels = mutants(src, "argument_drop").map(&:label)
      expect(labels).to(include("drop arg `build(`"))
      expect(labels).to(include("drop arg `other`"))
      expect(labels).not_to(include("drop arg `  ), other`")) # would be `first`=>`last`
    end
  end

  # No suite asserts its own log lines, and a memo guard is equivalent for pure code.
  describe "default-set noise suppression" do
    it "statement_deletion skips logger calls, whatever the chain", :aggregate_failures do
      expect(mutants("def m(x)\n  Rails.logger.debug { x }\nend\n", "statement_deletion")).to(be_empty)
      expect(mutants("def m(x)\n  logger.info(x)\nend\n", "statement_deletion")).to(be_empty)
      expect(mutants("def m(x)\n  @logger&.warn(x)\nend\n", "statement_deletion")).to(be_empty)
      expect(mutants("def m(x)\n  puts x\nend\n", "statement_deletion")).to(be_empty)
    end

    it "statement_deletion still deletes a side effect reached through Rails" do
      expect(only("def m\n  Rails.cache.clear\nend\n", "statement_deletion").label)
        .to(eq("delete `Rails.cache.clear`"))
    end

    it "statement_deletion keeps deleting receiverless calls that are not output" do
      expect(only("def m\n  save!\nend\n", "statement_deletion").label).to(eq("delete `save!`"))
    end

    it "statement_deletion finds a logger deeper in the chain" do
      expect(mutants("def m(x)\n  Rails.logger.tagged(:a).info(x)\nend\n", "statement_deletion"))
        .to(be_empty)
    end

    it "conditional skips a memoization guard but not an ordinary early return", :aggregate_failures do
      expect(mutants("def m\n  return @x if defined?(@x)\n\n  @x = compute\nend\n", "conditional"))
        .to(be_empty)
      expect(mutants("def m(x)\n  return :none if x.nil?\n\n  x\nend\n", "conditional").size)
        .to(eq(2))
    end

    it "conditional and boolean_literal skip a guard-style memo but not its neighbours", :aggregate_failures do
      value = "def m\n  return @x if @x\n\n  @x = compute\nend\n"
      flag = "def m\n  return if @done\n  @done = true\n  work\nend\n"
      expect(mutants(value, "conditional")).to(be_empty)
      expect(mutants(flag, "conditional")).to(be_empty)
      expect(mutants(flag, "boolean_literal")).to(be_empty)
      expect(mutants("#{flag}def n\n  return if @stopped\n  work(true)\nend\n", "conditional").size).to(eq(2))
      expect(mutants("#{flag}def n\n  return if @stopped\n  work(true)\nend\n", "boolean_literal").size).to(eq(1))
    end
  end

  describe "guard precision: matchers stay silent off-target" do
    it "argument_drop skips argument lists containing a splat" do
      expect(mutants("def m(xs)\n  pay(1, *xs)\nend\n", "argument_drop")).to(be_empty)
    end

    it "arithmetic ignores operator-named calls with extra arguments" do
      expect(mutants("def m(a)\n  a.+(1, 2)\nend\n", "arithmetic")).to(be_empty)
    end

    it "comparison ignores operator-named calls with extra arguments" do
      expect(mutants("def m(a)\n  a.==(1, 2)\nend\n", "comparison")).to(be_empty)
    end

    it "collection_literal leaves an empty array literal alone" do
      expect(mutants("def a\n  []\nend\n", "collection_literal")).to(be_empty)
    end

    it "collection_literal leaves an empty hash literal alone" do
      expect(mutants("def h\n  {}\nend\n", "collection_literal")).to(be_empty)
    end

    it "method_unwrap only unwraps its curated method set" do
      expect(mutants("def m(x)\n  x.foo\nend\n", "method_unwrap")).to(be_empty)
    end

    it "method_unwrap requires an explicit receiver" do
      expect(mutants("def m\n  dup\nend\n", "method_unwrap")).to(be_empty)
    end

    it "negation ignores a ! call carrying arguments" do
      expect(mutants("def m(a, b)\n  a.!(b)\nend\n", "negation")).to(be_empty)
    end

    it "op_assign leaves non-arithmetic compound assignment alone" do
      expect(mutants("def m(x, y)\n  x <<= y\n  x\nend\n", "op_assign")).to(be_empty)
    end

    it "regexp leaves the empty regexp alone" do
      expect(mutants("def re\n  //\nend\n", "regexp")).to(be_empty)
    end

    it "return_value does not propose nil for a nil tail" do
      expect(mutants("def m\n  nil\nend\n", "return_value")).to(be_empty)
    end

    it "selector_swap requires an explicit receiver" do
      expect(mutants("def m\n  first\nend\n", "selector_swap")).to(be_empty)
    end

    # Without the SWAPS guard it would propose `strip => ` for every call.
    it "selector_swap ignores a call whose message has no dual" do
      expect(mutants("def m(s)\n  s.strip\nend\n", "selector_swap")).to(be_empty)
    end

    it "string_literal leaves the empty string alone" do
      expect(mutants("def s\n  \"\"\nend\n", "string_literal")).to(be_empty)
    end

    it "rails_permit requires a receiver on permit" do
      expect(mutants("def m\n  permit(:name)\nend\n", "rails_permit")).to(be_empty)
    end
  end
end
