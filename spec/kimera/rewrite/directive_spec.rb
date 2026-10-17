# frozen_string_literal: true

require "kimera/rewrite/directive"

RSpec.describe(Kimera::Rewrite::Directive) do
  describe "#render" do
    it "renders a comparison variant from a directive" do
      out = described_class.new({ "type" => "comparison", "to" => "<" }).render("a > b")
      expect(out).to(eq("a < b"))
    end

    it "renders a boolean connective variant" do
      out = described_class.new({ "type" => "boolean_connective", "to" => "or" }).render("a && b")
      expect(out).to(eq("a || b"))
    end

    # unparser prints `a || b and "c"` for this: a syntax error once it sits in an
    # argument list (thor's `Shellwords.split(ENV["THOR_DIFF"] || ENV["RAILS_DIFF"] || "diff -u")`).
    it "parenthesizes a nested connective so the variant stays valid in any context" do
      out = described_class.new({ "type" => "boolean_connective", "to" => "and" }).render('a || b || "c"')
      expect(out).to(eq('(a || b) && "c"'))
    end

    it "renders a boolean literal variant" do
      out = described_class.new({ "type" => "boolean_literal", "to" => "false" }).render("true")
      expect(out).to(eq("false"))
    end

    it "labels statement deletion specially without parsing" do
      out = described_class.new({ "type" => "statement_deletion" }).render("do_thing(x)")
      expect(out).to(eq("(statement deleted)"))
    end

    it "renders a string segment of an interpolation, which does not parse alone" do
      expect(described_class.new({ "type" => "string_literal", "value" => "" }).render("; boundary=")).to(eq('""'))
    end

    # Unparsing the whole node would print a modifier `if` as an if/end block.
    it "writes a forced condition into the original text, keeping its shape", :aggregate_failures do
      forced = ->(source, to) { described_class.new({ "type" => "condition", "to" => to }).render(source) }
      expect(forced.call("return false if order_total <= 0", "false")).to(eq("return false if false"))
      expect(forced.call("x unless ready?", "true")).to(eq("x unless true"))
      expect(forced.call("é < 0 ? 0 : é", "true")).to(eq("true ? 0 : é"))
      expect(forced.call("if a\n  b\nend", "false")).to(eq("if false\n  b\nend"))
    end

    it "forces only a condition directive, never another one that names a target" do
      expect(described_class.new({ "type" => "boolean_literal", "to" => "false" }).render("x if y")).to(eq("false"))
    end

    it "falls back to unparsing a condition that does not parse alone" do
      out = described_class.new({ "type" => "condition", "to" => "true" }).render("x if")
      expect(out).to(be_nil)
    end

    it "returns nil when the snippet cannot be rendered cleanly" do
      expect(described_class.new({ "type" => "bogus" }).render("a > b")).to(be_nil)
    end

    # Without the hash check this crashes on the symbol arg and render returns nil.
    it "leaves a call without keyword arguments untouched by a kwarg drop" do
      out = described_class.new({ "type" => "kwarg_pair_drop", "key" => "dependent" }).render("has_many :posts")
      expect(out).to(eq("has_many(:posts)"))
    end

    it "kwarg drop matches symbol keys only, ignoring string keys" do
      out = described_class.new({ "type" => "kwarg_pair_drop", "key" => "dependent" })
        .render('has_many :posts, "dependent" => :destroy')
      expect(out).to(eq('has_many(:posts, "dependent" => :destroy)'))
    end

    # A block call parses as :block wrapping the send. Without unwrapping, the
    # mutant equals the original and always survives.
    it "drops a kwarg pair from a call that carries a block" do
      out = described_class.new({ "type" => "kwarg_pair_drop", "key" => "expires_in" })
        .render("Rails.cache.fetch(key, expires_in: 5) { total }")
      expect(out).to(eq("Rails.cache.fetch(key) {\n  total\n}"))
    end

    it "drops a kwarg array element from a call that carries a block" do
      out = described_class.new({ "type" => "kwarg_element_drop", "key" => "on", "index" => 0 })
        .render("after_commit on: [:create, :update] do\n  sync\nend")
      expect(out).to(eq("after_commit(on: [:update]) {\n  sync\n}"))
    end
  end

  describe "#apply" do
    it "raises on an unknown directive type, naming the directive" do
      node = Unparser.parse("a > b")
      expect { described_class.new({ "type" => "mystery" }).apply(node) }
        .to(raise_error(ArgumentError, /unknown directive .*mystery/))
    end
  end
end
