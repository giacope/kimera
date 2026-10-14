# frozen_string_literal: true

# Runs no sections itself: it only checks that whatever ran before it left
# the process-wide stack empty.
RSpec.describe "Outline at top level" do
  it "has no open sections" do
    expect(Outline.depth).to eq(0)
    expect(Outline.path).to eq("")
    expect(Outline.number).to eq("")
  end
end
