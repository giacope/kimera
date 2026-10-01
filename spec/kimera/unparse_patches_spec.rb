# frozen_string_literal: true

require "kimera/support/unparse"

# Kimera::Unparse prepends onto unparser's internals, which are not public
# API. When an unparser upgrade renames or drops one of them, a prepended
# override stops being called and the workaround silently lapses. These
# checks fail first, so the gemspec's pin is raised only with the patches.
RSpec.describe(Kimera::Unparse) do
  def upstream?(method) = method && !method.owner.name.to_s.start_with?("Kimera::")

  {
    [Unparser::Emitter::Range, :visit_begin_node] => Kimera::Unparse::RangeEndpoints,
    [Unparser::Emitter::Range, :visit_end_node] => Kimera::Unparse::RangeEndpoints,
    [Unparser::AST::LocalVariableScopeEnumerator, :enter] => Kimera::Unparse::Binders
  }.each do |(target, name), patch|
    it "#{target}##{name} is still defined by the gem, under #{patch}", :aggregate_failures do
      method = target.instance_method(name)
      expect(method.owner).to(eq(patch))
      expect(upstream?(method.super_method)).to(be(true), "#{target}##{name} is gone from unparser")
    end
  end

  it "Unparser.parser still exists and builds a parser with a builder", :aggregate_failures do
    method = Unparser.method(:parser)
    expect(method.owner).to(eq(Kimera::Unparse::Parsing))
    expect(upstream?(method.super_method)).to(be(true))
    expect(Unparser.parser.builder).to(be_a(Kimera::Unparse::RawBytes))
  end

  it "the builder still reports encoding problems through #diagnostic" do
    expect(upstream?(Unparser.parser.builder.method(:diagnostic).super_method)).to(be(true))
  end

  it "the helpers the patches call are still there", :aggregate_failures do
    expect(Unparser::Emitter::Range.private_method_defined?(:n_array?)).to(be(true))
    expect(Unparser::Emitter::Range.private_method_defined?(:visit)).to(be(true))
    expect(Unparser::AST::LocalVariableScopeEnumerator.private_method_defined?(:define)).to(be(true))
  end
end
