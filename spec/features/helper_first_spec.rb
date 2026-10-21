# frozen_string_literal: true

require "fileutils"
require "tmpdir"

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

  it "loads the helper before the test files that rely on it" do
    Dir.mktmpdir("kimera-helper") do |root|
      files.each do |path, body|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), body)
      end
      arguments = ["--framework", "minitest", "--no-progress", "--tests", "test/**/*_test.rb"]
      test_run(cwd: root, tests: "test/helper.rb", arguments: arguments) do |output, report, _status|
        expect(report).not_to(be_nil, output)
        expect(report.fetch("counts")["killed"]).to(eq(report.fetch("counts")["total"]))
      end
    end
  end
end
