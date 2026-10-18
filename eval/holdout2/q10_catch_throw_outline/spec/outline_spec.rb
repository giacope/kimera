# frozen_string_literal: true

RSpec.describe Outline do
  describe ".section" do
    it "exposes the path and number while open" do
      seen = described_class.section("Intro") do
        described_class.section(" Scope ", 2) { [described_class.path, described_class.number, described_class.depth] }
      end
      expect(seen).to eq(["Intro > Scope", "1.2", 2])
    end

    it "returns what skip! throws" do
      result = described_class.section("Draft") do
        described_class.skip!
        :unreachable
      end
      expect(result).to eq(:skipped)
    end

    it "closes the section when the block raises" do
      expect { described_class.section("Boom") { raise "x" } }.to raise_error("x")
      expect(described_class.path).to eq("")
    end

    it "refuses blank titles" do
      expect { described_class.section("  ") { nil } }.to raise_error(ArgumentError, /title required/)
    end

    it "allows four levels and no more" do
      deepest = described_class.section("a") do
        described_class.section("b") do
          described_class.section("c") { described_class.section("d") { described_class.number } }
        end
      end
      expect(deepest).to eq("1.1.1.1")
      expect do
        described_class.section("a") do
          described_class.section("b") { described_class.section("c") { described_class.section("d") { described_class.section("e") { nil } } } }
        end
      end.to raise_error(ArgumentError, /deeper than 4/)
    end
  end

  describe ".skip!" do
    it "fails outside a section" do
      expect { described_class.skip! }.to raise_error(Outline::NotInSection)
    end
  end

  describe ".render" do
    let(:tree) do
      {
        "Overview" => {},
        "_Notes" => { "Ignored" => {} },
        "Design" => { "Storage" => {}, "_Todo" => {}, "Network" => { "Retries" => {} } },
        "Rollout" => {}
      }
    end

    it "numbers and indents sections, skipping drafts" do
      expect(described_class.render(tree)).to eq([
        "1 Overview",
        "2 Design",
        "  2.1 Storage",
        "  2.2 Network",
        "    2.2.1 Retries",
        "3 Rollout"
      ])
    end

    it "takes a custom indent" do
      expect(described_class.render({ "A" => { "B" => {} } }, indent: 0)).to eq(["1 A", "1.1 B"])
    end

    it "rejects a negative indent" do
      expect { described_class.render({}, indent: -1) }.to raise_error(ArgumentError)
    end
  end
end
