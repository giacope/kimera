# frozen_string_literal: true

require "kimera/synthesis/overlay"

RSpec.describe(Kimera::SuperclassPin) do
  it "lets a Data.define or Struct.new subclass be evaluated twice", :aggregate_failures do
    source = <<~RUBY
      module KimeraPinned
        class Usage < Data.define(:used)
          def double = used * 2
        end
      end
      class KimeraPinnedPair < Struct.new(:a); end
    RUBY
    2.times { Kimera::Overlay::Source.new(source).evaluate("pinned.rb") }
    expect(KimeraPinned::Usage.new(used: 2).double).to(eq(4))
    expect(KimeraPinnedPair.new(1).a).to(eq(1))
  end

  it "keeps a class's superclass when the constant it names was rebound", :aggregate_failures do
    stub_const("KimeraRebound", Module.new)
    source = <<~RUBY
      module KimeraRebound
        Row = Data.define(:cells)
        class PersonRow < Row
          def wide? = cells > 3
        end
      end
    RUBY
    Kimera::Overlay::Source.new(source).evaluate("rebound.rb")
    first = KimeraRebound::Row
    Kimera::Overlay::Source.new(source).evaluate("rebound.rb")
    expect(KimeraRebound::PersonRow.superclass).to(equal(first))
    expect(KimeraRebound::PersonRow.new(cells: 4).wide?).to(be(true))
  end

  it "pins a class named by a path against that path's owner", :aggregate_failures do
    stub_const("KimeraPinPath", Module.new)
    source = "KimeraPinPath::Base = Class.new\nclass KimeraPinPath::Leaf < KimeraPinPath::Base; end\n"
    Kimera::Overlay::Source.new(source).evaluate("path.rb")
    first = KimeraPinPath::Base
    Kimera::Overlay::Source.new(source).evaluate("path.rb")
    expect(KimeraPinPath::Leaf.superclass).to(equal(first))
    expect(described_class.pin("class ::KimeraRooted < Base; end\n"))
      .to(eq("class ::KimeraRooted < (::Kimera::SuperclassPin.existing(::Object, :KimeraRooted) || Base); end\n"))
  end

  it "leaves a class without a superclass alone" do
    source = "module KimeraBare\n  class Plain; end\nend\n"
    expect(described_class.pin(source)).to(eq(source))
  end

  it "looks the class up in its lexical scope, not in self" do
    stub_const("KimeraLexical", Module.new)
    stub_const("KimeraLexicalHost", Class.new)
    stub_const("KimeraLexicalHost::Row", Class.new(ArgumentError))
    source = "module KimeraLexical\n  KimeraLexicalHost.class_eval do\n    class Row < StandardError; end\n  end\nend\n"
    Kimera::Overlay::Source.new(source).evaluate("lexical.rb")
    expect(KimeraLexical::Row.superclass).to(equal(StandardError))
  end

  it "pins nothing for a constant that is not a class or is only inherited", :aggregate_failures do
    stub_const("KimeraPinModule", Module.new)
    expect(described_class.existing(nil, :KimeraPinModule)).to(be_nil)
    expect(described_class.existing(Module.new, :String)).to(be_nil)
    expect(described_class.existing(nil, :KimeraPinMissing)).to(be_nil)
    expect(described_class.existing(nil, :ArgumentError)).to(equal(StandardError))
  end

  it "ignores a same-named constant outside the enclosing namespace" do
    stub_const("KimeraShadow", Class.new(StandardError))
    stub_const("KimeraShadowed", Module.new)
    source = "module KimeraShadowed\n  class KimeraShadow < Struct.new(:a); end\nend\n"
    Kimera::Overlay::Source.new(source).evaluate("shadow.rb")
    expect(KimeraShadowed::KimeraShadow.new(1).a).to(eq(1))
  end
end
