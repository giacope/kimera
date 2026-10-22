# frozen_string_literal: true

# Table::RATES is built while the suite loads, before any guard exists, so a
# warm run of a Rate.compute mutant can't change it.
RSpec.describe("kimera run on a method that also ran while the suite loaded (end-to-end)", :aggregate_failures) do
  def files = {
    "app/rate.rb" => "class Rate\n  def self.compute(x)\n    x > 10 ? 2 : 1\n  end\nend\n",
    "app/table.rb" => <<~RUBY,
      require_relative "rate"

      class Table
        RATES = (1..20).to_h { |x| [x, Rate.compute(x)] }.freeze

        def self.lookup(x) = RATES.fetch(x)
      end
    RUBY
    "spec/table_spec.rb" => <<~RUBY
      require_relative "../app/table"

      RSpec.describe Table do
        it("looks up the low rate at 10") { expect(Table.lookup(10)).to eq(1) }
        it("looks up the high rate at 11") { expect(Table.lookup(11)).to eq(2) }
        it("computes a low rate directly") { expect(Rate.compute(5)).to eq(1) }
      end
    RUBY
  }

  def ran = test_tree(files, "kimera-boot") { |root| test_outcome(cwd: root, arguments: ["--no-progress"]) }

  it "judges its warm survivors again against the whole suite, in fresh mirrors" do
    run = ran
    notes = run.results.filter_map { |row| row["note"] }
    expect([run.statuses, notes.size, run.status]).to(eq([["killed"], 2, 0]), run.output)
  end
end
