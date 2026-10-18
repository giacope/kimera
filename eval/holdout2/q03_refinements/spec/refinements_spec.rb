# frozen_string_literal: true

using TextKit::Refinements

RSpec.describe TextKit::Refinements do
  it "squishes whitespace" do
    expect("  a \t b\n c ".squish).to eq("a b c")
  end

  it "keeps minor words lowercase except first and last" do
    expect("of mice and men".title_case).to eq("Of Mice and Men")
    expect("what it is for".title_case).to eq("What It Is For")
  end

  it "truncates with a custom omission" do
    expect("a b c d".truncate_words(2, omission: " (more)")).to eq("a b (more)")
  end

  it "slugifies with a custom separator" do
    expect("Big -- Deal".slugify("_")).to eq("big_deal")
  end

  it "refines exactly String and Integer" do
    expect(described_class.refinements.map(&:target)).to contain_exactly(String, Integer)
  end
end
