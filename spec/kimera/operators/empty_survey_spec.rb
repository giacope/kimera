# frozen_string_literal: true

require "kimera/operators"

RSpec.describe(Kimera::Operators::EmptySurvey) do
  let(:node) { Kimera::Syntax.parse("def total = 1").value.statements.body.first }

  it "finds no node, so an operator that has surveyed no file mutates nothing" do
    expect([described_class.new.include?(node), Kimera::Operators::Visibility.new.variants(node)]).to(eq([false, nil]))
  end
end
