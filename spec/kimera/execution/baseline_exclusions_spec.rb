# frozen_string_literal: true

require "kimera/execution/baseline_exclusions"

RSpec.describe(Kimera::Execution::BaselineExclusions) do
  def notice(failures) = described_class.new(failures).to_s

  def numbered(count) = (1..count).to_h { |n| ["t#{n}", "boom #{n}"] }

  it "says nothing when no failing test was excluded" do
    expect(notice({})).to(be_nil)
  end

  it "names each excluded test with the first line of its failure" do
    expect(notice("t1" => "  Error: boom  \n    frame.rb:1")).to(end_with(":\n  t1: Error: boom"))
  end

  it "names a test whose failure carries no message on its own" do
    expect(notice("t1" => nil, "t2" => "")).to(end_with(":\n  t1\n  t2"))
  end

  it "counts every excluded test in its headline" do
    expect(notice(numbered(7))).to(start_with("kimera: 7 failing test(s) cover no in-scope mutant"))
  end

  it "lists every test up to the limit without an overflow line" do
    expect(notice(numbered(described_class::LISTED)).lines.last).to(eq("  t5: boom 5"))
  end

  it "folds the tests past the limit into a count" do
    expect(notice(numbered(described_class::LISTED + 2)).lines.last(2)).to(eq(["  t5: boom 5\n", "  … and 2 more"]))
  end
end
