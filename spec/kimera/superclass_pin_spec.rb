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
    2.times { Kimera::Overlay.evaluate(source, "pinned.rb") }
    expect(KimeraPinned::Usage.new(used: 2).double).to(eq(4))
    expect(KimeraPinnedPair.new(1).a).to(eq(1))
  end

  it "leaves constant superclasses untouched" do
    source = "class KimeraPlain < StandardError; end\n"
    expect(described_class.pin(source)).to(eq(source))
  end
end
