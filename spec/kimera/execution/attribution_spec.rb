# frozen_string_literal: true

require "kimera/execution/attribution"

RSpec.describe(Kimera::Execution::Attribution, :aggregate_failures) do
  subject(:attribution) { described_class.new }

  describe "the usual layouts" do
    it "maps a lib file to its spec or test under the same path" do
      expect(attribution.own?("spec/kimera/cli/run_spec.rb", "lib/kimera/cli/run.rb")).to(be(true))
      expect(attribution.own?("spec/lib/kimera/cli/run_spec.rb", "lib/kimera/cli/run.rb")).to(be(true))
      expect(attribution.own?("test/kimera/cli/run_test.rb", "lib/kimera/cli/run.rb")).to(be(true))
      expect(attribution.own?("test/kimera/cli/test_run.rb", "lib/kimera/cli/run.rb")).to(be(true))
    end

    it "maps a top-level lib file to a test_ file at the test root" do
      expect(attribution.own?("test/test_inflector.rb", "lib/inflector.rb")).to(be(true))
    end

    it "maps a Rails app file to its spec or test with or without the app kind" do
      expect(attribution.own?("spec/models/order_spec.rb", "app/models/order.rb")).to(be(true))
      expect(attribution.own?("test/models/order_test.rb", "app/models/order.rb")).to(be(true))
      expect(attribution.own?("spec/order_spec.rb", "app/models/order.rb")).to(be(true))
      expect(attribution.own?("spec/app/models/order_spec.rb", "app/models/order.rb")).to(be(true))
    end

    it "does not count another unit's tests, or a request spec of a controller" do
      expect(attribution.own?("spec/models/account_spec.rb", "app/models/order.rb")).to(be(false))
      expect(attribution.own?("spec/requests/orders_spec.rb", "app/controllers/orders_controller.rb")).to(be(false))
      expect(attribution.own?("spec/kimera/cli_spec.rb", "lib/kimera/cli/run.rb")).to(be(false))
      expect(attribution.own?("spec/order_spec.rb", "lib/models/order.rb")).to(be(false))
    end

    it "names the two usual test files for a source" do
      expect(attribution.expected("app/models/order.rb")).to(
        eq(
          %w[spec/models/order_spec.rb
            test/models/order_test.rb]
        )
      )
      expect(attribution.expected("lib/a/b.rb")).to(eq(%w[spec/a/b_spec.rb test/a/b_test.rb]))
      expect(attribution.expected("tools/x.rb")).to(eq(%w[spec/tools/x_spec.rb test/tools/x_test.rb]))
    end
  end

  describe "unit_tests rules" do
    subject(:attribution) { described_class.new(rules) }

    let(:rules) do
      { "app/services/**/*.rb" => "spec/units/{path}_check.rb", "lib/**/*.rb" => ["test/**/{name}_case.rb"] }
    end

    it "fills {path} under the glob's literal prefix and {name}, and matches the pattern as a glob" do
      expect(attribution.own?("spec/units/billing/charge_check.rb", "app/services/billing/charge.rb")).to(be(true))
      expect(attribution.own?("test/deep/down/charge_case.rb", "lib/charge.rb")).to(be(true))
      expect(attribution.own?("test/charge_case.rb", "lib/charge.rb")).to(be(true))
    end

    it "applies a rule only to the sources its glob matches, beside the usual layouts" do
      expect(attribution.own?("spec/units/charge_check.rb", "app/services/billing/charge.rb")).to(be(false))
      expect(attribution.own?("test/charge_case.rb", "app/models/charge.rb")).to(be(false))
      expect(attribution.own?("spec/units/billing/charge_check.rb", "app/models/billing/charge.rb")).to(be(false))
      expect(attribution.own?("spec/services/billing/charge_spec.rb", "app/services/billing/charge.rb")).to(be(true))
    end
  end
end
