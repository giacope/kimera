# frozen_string_literal: true

require "kimera/synthesis/readback"

# A whole-method or whole-file write is kept only when it reads back as the
# tree meant (R6B4-M1..M3).
RSpec.describe(Kimera::Readback) do
  def tree(source) = Kimera::Syntax.parse(source).value

  it "reads a file back as the file, and a method as the method", :aggregate_failures do
    expect(described_class.new(tree("class A\nend\n")).faithful?("class A; end")).to(be(true))
    expect(described_class.new(tree("def a = 1").statements.body.first).faithful?("def a\n  1\nend")).to(be(true))
  end

  it "refuses a text that reads as another tree, or none" do
    meant = tree("case v\nwhen 90.. then 1\nend\n").statements.body.first
    texts = ["case v\nwhen 90..\n  1\nend", "case v\nwhen 90..;\n  1\nend", "case v"]
    expect(texts.map { described_class.new(meant).faithful?(it) }).to(eq([false, true, false]))
  end
end
