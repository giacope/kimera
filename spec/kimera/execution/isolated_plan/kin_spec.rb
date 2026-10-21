# frozen_string_literal: true

require "kimera/execution/isolated_kin"
require "kimera/registry/builder"

# A mutant only the isolated tier can judge (a validation, a callback) has no
# coverage of its own; it runs the tests in the files that cover its source
# file, plus that file's conventional spec or test file, not the whole suite.
RSpec.describe(Kimera::Execution::IsolatedPlan::Kin) do
  let(:registry) do
    Kimera::RegistryScan.new.source("class User\n  def adult?(age) = age > 17\nend\n", file: "app/models/user.rb")
  end

  let(:id) { registry.each.first.first.id }

  let(:users) { %w[./spec/models/user_spec.rb[1:1] ./spec/models/user_spec.rb[1:2] ./spec/requests/user_spec.rb[1:1]] }
  let(:all) { [*users, "./spec/models/order_spec.rb[1:1]", "./spec/lib/report_spec.rb[1:1]"] }

  def kin(coverage) = described_class.new(all: all, coverage: coverage, registry: registry)

  it "runs every test in the files that cover the source file, and its conventional spec files" do
    expect(kin({ id => ["./spec/lib/report_spec.rb[1:1]"] }).tests("app/models/user.rb"))
      .to(eq([*users, "./spec/lib/report_spec.rb[1:1]"]))
  end

  it "maps test ids to files through the adapter's paths" do
    tests = %w[UserTest#test_a OrderTest#test_b ReportTest#test_c]
    paths = {
      "UserTest#test_a" => "/p/test/user_test.rb", "OrderTest#test_b" => "/p/test/order_test.rb",
      "ReportTest#test_c" => "/p/test/report_test.rb"
    }
    locate = paths.method(:fetch)
    narrowed = described_class.new(all: tests, coverage: { id => ["OrderTest#test_b"] }, registry: registry, locate:)
    expect(narrowed.tests("app/models/user.rb")).to(eq(tests.first(2)))
  end

  it "runs the whole suite where coverage names no test of the file", :aggregate_failures do
    expect(kin({}).tests("app/models/user.rb")).to(eq(all))
    expect(kin({ id => ["./spec/gone_spec.rb[1:1]"] }).tests("app/models/user.rb").size).to(eq(3))
  end
end
