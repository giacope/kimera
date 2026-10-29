# frozen_string_literal: true

require "kimera/synthesis/guardrail_factories"

RSpec.describe(Kimera::Factory) do
  it "names the core calls that make a class from a block", :aggregate_failures do
    made = [%i[Struct new], %i[Data define], %i[Class new], %i[Module new]]
    expect(made.map { |receiver, name| described_class.new(receiver, name).named? }).to(all(be(true)))
    unmade = [described_class.new(:Struct, :define), described_class.new(:Hash, :new)]
    expect(unmade.map(&:named?)).to(eq([false, false]))
  end
end
