# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Cart's spec runs Price too, so by default it kills Price's mutants. Under
# strict attribution only Price's own tests may, and it has none.
RSpec.describe("kimera run --attribution unit (end-to-end)", :aggregate_failures) do
  def test_shop(root)
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
    }.each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), body)
    end
  end

  def statuses(report, file) = report["results"].select { |r| r["file"] == file }.map { |r| r["status"] }.uniq

  def shop(arguments)
    Dir.mktmpdir("kimera-attribution") do |root|
      test_shop(root)
      test_run(cwd: root, arguments: arguments) do |output, report, status|
        expect(report).not_to(be_nil, "no JSON report; output:\n#{output}")
        yield(report, status, output)
      end
    end
  end

  it "kills Price's mutants by Cart's spec by default" do
    shop([]) do |report, status|
      expect([statuses(report, "app/shop/price.rb"), status]).to(eq([["killed"], 0]))
    end
  end

  it "reports Price's mutants uncovered_by_unit, gated as survivors, under --attribution unit" do
    shop(%w[--attribution unit]) do |report, status, output|
      price = report["results"].select { |r| r["file"] == "app/shop/price.rb" }
      expect(price.map { |r| r["status"] }.uniq).to(eq(["uncovered_by_unit"]))
      expect(price.first["covering_tests"]).to(all(start_with("./spec/shop/cart_spec.rb")))
      expect(price.first["detail"]).to(include("spec/shop/price_spec.rb, test/shop/price_test.rb"))
      expect(statuses(report, "app/shop/cart.rb")).to(eq(["killed"]))
      expect(report["counts"]["uncovered_by_unit"]).to(eq(price.size))
      expect(report["run"]).to(include("attribution" => "unit"))
      expect(output).to(include("Reached only by other units' tests (#{price.size}):"))
      expect(output).to(include("gate failed: survivors=#{price.size} (#{price.size} uncovered_by_unit)"))
      expect(status).to(eq(2))
    end
  end

  it "counts a test a unit_tests rule names as the unit's own" do
    shop(%w[--attribution unit --unit-tests app/shop/price.rb=spec/shop/cart_spec.rb]) do |report, status|
      expect([statuses(report, "app/shop/price.rb"), status]).to(eq([["killed"], 0]))
    end
  end
end
