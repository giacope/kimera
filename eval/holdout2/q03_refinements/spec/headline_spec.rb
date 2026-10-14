# frozen_string_literal: true

RSpec.describe TextKit::Headline do
  describe "#display" do
    it "prefixes the ordinal rank and title-cases the text" do
      expect(described_class.new("the  rise of   ruby", rank: 1).display).to eq("1st: The Rise of Ruby")
    end

    it "truncates long titles after six words" do
      headline = described_class.new("one two three four five six seven", rank: 2)
      expect(headline.display).to eq("2nd: One Two Three Four Five Six...")
    end

    it "keeps a six word title whole" do
      expect(described_class.new("one two three four five six", rank: 3).display)
        .to eq("3rd: One Two Three Four Five Six")
    end

    it "uses th for the teens" do
      expect(described_class.new("x", rank: 12).display).to eq("12th: X")
      expect(described_class.new("x", rank: 111).display).to eq("111th: X")
    end

    it "uses st/nd/rd past the teens" do
      expect(described_class.new("x", rank: 21).display).to eq("21st: X")
      expect(described_class.new("x", rank: 102).display).to eq("102nd: X")
    end

    it "rejects a rank below one" do
      expect { described_class.new("x", rank: 0) }.to raise_error(ArgumentError)
    end
  end

  describe "#short?" do
    it "is true up to three words" do
      expect(described_class.new("  big   news today ")).to be_short
      expect(described_class.new("big news today again")).not_to be_short
    end
  end

  describe "#slug" do
    it "builds a lowercase dashed slug" do
      expect(described_class.new("  Hello, World!  ").slug).to eq("hello-world")
    end

    it "numbers repeated slugs" do
      first = described_class.new("Ruby 4.0 Released").slug
      second = described_class.new("ruby 4.0: released").slug
      expect([first, second]).to eq(["ruby-4-0-released", "ruby-4-0-released-2"])
    end

    it "memoises the slug per headline" do
      headline = described_class.new("Memo Test Slug")
      expect(headline.slug).to equal(headline.slug)
    end
  end
end
