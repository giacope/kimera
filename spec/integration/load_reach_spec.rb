# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# The suite reaches Pricing#price only through an alias and an alias_method
# declared in other files, and Fees::Hook#charges only through a macro another
# file's class body calls while it loads. Both used to come out uncovered,
# though the suite kills every one of these mutants.
RSpec.describe("kimera run on code reached through another file (end-to-end)", :aggregate_failures) do
  def test_shop(root)
    {
      "app/shop.rb" => <<~RUBY,
        module Shop; end
        require_relative "shop/pricing"
        require_relative "shop/fees"
        require_relative "shop/aliased"
        require_relative "shop/renamed"
        require_relative "shop/macro"
      RUBY
      "app/shop/pricing.rb" => <<~RUBY,
        module Shop::Pricing
          def price(amount)
            return 0 if amount.negative?
            amount * 2
          end
        end
      RUBY
      "app/shop/aliased.rb" => "class Shop::Aliased\n  include Shop::Pricing\n\n  alias cost price\nend\n",
      "app/shop/renamed.rb" => "class Shop::Renamed\n  include Shop::Pricing\n\n  alias_method :fee, :price\nend\n",
      "app/shop/fees.rb" => <<~RUBY,
        module Shop::Fees
          def self.included(base) = base.extend(Hook)

          module Hook
            def charges(name) = define_method(name) { |amount| amount + 1 }
          end
        end
      RUBY
      "app/shop/macro.rb" => "class Shop::Macro\n  include Shop::Fees\n\n  charges :cost\nend\n",
      "spec/shop_spec.rb" => <<~RUBY
        require_relative "../app/shop"

        RSpec.describe Shop::Aliased do
          it("doubles") { expect(described_class.new.cost(3)).to eq(6) }
          it("floors negatives at zero") { expect(Shop::Renamed.new.fee(-3)).to eq(0) }
        end

        RSpec.describe Shop::Macro do
          it("adds one") { expect(described_class.new.cost(3)).to eq(4) }
        end
      RUBY
    }.each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), body)
    end
  end

  it "kills the aliased mutants and sends the macro's to the isolated tier, never uncovered" do
    Dir.mktmpdir("kimera-reach") do |root|
      test_shop(root)
      test_run(cwd: root, args: ["--fail-on-no-coverage"]) do |output, report, status|
        expect(report).not_to(be_nil, "no JSON report; output:\n#{output}")
        results = report["results"]
        pricing, fees = %w[app/shop/pricing.rb app/shop/fees.rb].map { |file| results.select { |r| r["file"] == file } }
        expect(pricing.map { |r| r["status"] }.uniq).to(eq(["killed"]))
        expect(fees.map { |r| r["status"] }.uniq).to(eq(["isolated_only"]))
        expect(fees.map { |r| r["detail"] }).to(all(start_with("runs only while the suite loads")))
        expect(report["counts"]["no_coverage"]).to(eq(0))
        expect(status).to(eq(0))
      end
    end
  end

  it "kills every one of them with --isolated" do
    Dir.mktmpdir("kimera-reach") do |root|
      test_shop(root)
      test_run(cwd: root, args: ["--isolated"]) do |output, report, status|
        expect(report).not_to(be_nil, "no JSON report; output:\n#{output}")
        expect(report["results"].map { |r| r["status"] }.uniq).to(eq(["killed"]))
        expect(report["counts"]["total"]).to(eq(4))
        expect(status).to(eq(0))
      end
    end
  end
end
