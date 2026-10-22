# frozen_string_literal: true

# Cart's spec runs Price too, so by default it kills Price's mutants. Under
# strict attribution only Price's own tests may, and it has none.
RSpec.describe("kimera run --attribution unit (end-to-end)", :aggregate_failures) do
  def shop_files
    {
      "app/shop.rb" => "module Shop; end\nrequire_relative \"shop/price\"\nrequire_relative \"shop/cart\"\n",
      "app/shop/price.rb" => "class Shop::Price\n  def gross(amount)\n    amount > 0 ? amount + 1 : 0\n  end\nend\n",
      "app/shop/cart.rb" => <<~RUBY,
        class Shop::Cart
          def total(amounts)
            return if amounts.empty?
            amounts.sum { |amount| Shop::Price.new.gross(amount) }
          end
        end
      RUBY
      "spec/shop/cart_spec.rb" => <<~RUBY
        require_relative "../../app/shop"

        RSpec.describe Shop::Cart do
          it("has no total when empty") { expect(described_class.new.total([])).to be_nil }
          it("adds a fee to each positive amount") { expect(described_class.new.total([1, 2, -3, 0])).to eq(5) }
        end
      RUBY
    }
  end

  def shop(arguments)
    test_tree(shop_files, "kimera-attribution") { |root| test_outcome(cwd: root, arguments: arguments) }
  end

  # What a unit-attributed run says of Price's mutants and of the rest.
  def unit_facts(run, price)
    {
      statuses: price.map { |r| r["status"] }.uniq, covering: price.first["covering_tests"],
      detail: price.first["detail"], cart: run.statuses("app/shop/cart.rb"),
      counted: run.report["counts"]["uncovered_by_unit"], attribution: run.report["run"]["attribution"],
      status: run.status
    }
  end

  it "kills Price's mutants by Cart's spec by default" do
    run = shop([])
    expect([run.statuses("app/shop/price.rb"), run.status]).to(eq([["killed"], 0]), run.output)
  end

  it "reports Price's mutants uncovered_by_unit, gated as survivors, under --attribution unit" do
    run = shop(%w[--attribution unit])
    price = run.results.select { |r| r["file"] == "app/shop/price.rb" }
    expect(unit_facts(run, price)).to(
      match(
        statuses: ["uncovered_by_unit"], covering: all(start_with("./spec/shop/cart_spec.rb")),
        detail: include("spec/shop/price_spec.rb, test/shop/price_test.rb"), cart: ["killed"],
        counted: price.size, attribution: "unit", status: 2
      )
    )
    expect(run.output).to(
      include(
        "Reached only by other units' tests (#{price.size}):",
        "gate failed: survivors=#{price.size} (#{price.size} uncovered_by_unit)"
      )
    )
  end

  it "counts a test a unit_tests rule names as the unit's own" do
    run = shop(%w[--attribution unit --unit-tests app/shop/price.rb=spec/shop/cart_spec.rb])
    expect([run.statuses("app/shop/price.rb"), run.status]).to(eq([["killed"], 0]), run.output)
  end
end
