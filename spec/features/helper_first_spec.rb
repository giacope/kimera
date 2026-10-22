# frozen_string_literal: true

# Spec-style Minitest files that never require their helper, which the
# project's Rake task preloads with -r: listing the helper first in `tests:`
# loads it first.
RSpec.describe("kimera run with a helper listed first in tests (end-to-end)", :aggregate_failures) do
  def files = {
    "app/calc.rb" => "class Calc\n  def positive?(n) = n > 0\nend\n",
    "test/helper.rb" => "require \"minitest/autorun\"\nrequire_relative \"../app/calc\"\n",
    "test/calc_test.rb" => <<~RUBY
      describe Calc do
        it("is positive above zero") { _(Calc.new.positive?(1)).must_equal true }
        it("is not positive at zero") { _(Calc.new.positive?(0)).must_equal false }
      end
    RUBY
  }

  def ran
    arguments = ["--framework", "minitest", "--no-progress", "--tests", "test/**/*_test.rb"]
    test_tree(files, "kimera-helper") { |root| test_outcome(cwd: root, tests: "test/helper.rb", arguments: arguments) }
  end

  it "loads the helper before the test files that rely on it" do
    run = ran
    expect(run.report).not_to(be_nil, run.output)
    expect(run.report.fetch("counts").values_at("killed", "total").uniq.size).to(eq(1))
  end
end
