# frozen_string_literal: true

require "kimera/rewrite/directive"

RSpec.describe(Kimera::Rewrite::Directive) do
  describe ".render" do
    it "renders a comparison variant from a directive" do
      out = described_class.render("a > b", { "type" => "comparison", "to" => "<" })
      expect(out).to(eq("a < b"))
    end

    it "renders a boolean connective variant" do
      out = described_class.render("a && b", { "type" => "boolean_connective", "to" => "or" })
      expect(out).to(eq("a || b"))
    end

    it "renders a boolean literal variant" do
      out = described_class.render("true", { "type" => "boolean_literal", "to" => "false" })
      expect(out).to(eq("false"))
    end

    it "labels statement deletion specially without parsing" do
      out = described_class.render("do_thing(x)", { "type" => "statement_deletion" })
      expect(out).to(eq("(statement deleted)"))
    end

    it "renders a string segment of an interpolation, which does not parse alone" do
      expect(described_class.render("; boundary=", { "type" => "string_literal", "value" => "" })).to(eq('""'))
    end

    it "returns nil when the snippet cannot be rendered cleanly" do
      expect(described_class.render("a > b", { "type" => "bogus" })).to(be_nil)
    end

    # Without the hash check this crashes on the symbol arg and render returns nil.
    it "leaves a call without keyword arguments untouched by a kwarg drop" do
      out = described_class.render("has_many :posts", { "type" => "kwarg_pair_drop", "key" => "dependent" })
      expect(out).to(eq("has_many(:posts)"))
    end

    it "kwarg drop matches symbol keys only, ignoring string keys" do
      out = described_class.render(
        'has_many :posts, "dependent" => :destroy',
        { "type" => "kwarg_pair_drop", "key" => "dependent" }
      )
      expect(out).to(eq('has_many(:posts, "dependent" => :destroy)'))
    end

    # A block call parses as :block wrapping the send. Without unwrapping, the
    # mutant equals the original and always survives.
    it "drops a kwarg pair from a call that carries a block" do
      out = described_class.render(
        "Rails.cache.fetch(key, expires_in: 5) { total }",
        { "type" => "kwarg_pair_drop", "key" => "expires_in" }
      )
      expect(out).to(eq("Rails.cache.fetch(key) {\n  total\n}"))
    end

    it "drops a kwarg array element from a call that carries a block" do
      out = described_class.render(
        "after_commit on: [:create, :update] do\n  sync\nend",
        { "type" => "kwarg_element_drop", "key" => "on", "index" => 0 }
      )
      expect(out).to(eq("after_commit(on: [:update]) {\n  sync\n}"))
    end
  end

  describe ".apply" do
    it "raises on an unknown directive type, naming the directive" do
      node = Unparser.parse("a > b")
      expect { described_class.apply(node, { "type" => "mystery" }) }
        .to(raise_error(ArgumentError, /unknown directive .*mystery/))
    end
  end
end
