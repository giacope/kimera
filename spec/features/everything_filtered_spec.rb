# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# An older RSpec idiom focuses on `focus: true` examples and falls back to
# all of them when none is focused; kimera loads examples as `rspec` does.
# A baseline whose filter still leaves nothing to run fails loudly instead of
# scoring every mutant as uncovered.
RSpec.describe("kimera run under an inclusion filter that matches nothing (end-to-end)", :aggregate_failures) do
  def files(fallback) = {
    ".rspec" => "--require spec_helper\n",
    "spec/spec_helper.rb" => <<~RUBY,
      RSpec.configure do |config|
        config.filter_run_including focus: true
        config.run_all_when_everything_filtered = #{fallback}
      end
    RUBY
    "app/calc.rb" => "class Calc\n  def positive?(n) = n > 0\nend\n",
    "spec/calc_spec.rb" => <<~RUBY
      require_relative "../app/calc"

      RSpec.describe Calc do
        it("is positive above zero") { expect(Calc.new.positive?(1)).to be(true) }
        it("is not positive at zero") { expect(Calc.new.positive?(0)).to be(false) }
      end
    RUBY
  }

  def project(root, fallback)
    files(fallback).each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), body)
    end
  end

  it "runs every example when the focus filter matches none and the suite asks for that" do
    Dir.mktmpdir("kimera-filtered") do |root|
      project(root, true)
      test_run(cwd: root, arguments: ["--no-progress"]) do |output, report, _status|
        expect(report).not_to(be_nil, output)
        expect(report.fetch("counts").slice("no_coverage", "survived")).to(eq({ "no_coverage" => 0, "survived" => 0 }))
        expect(report.fetch("counts")["killed"]).to(be_positive)
      end
    end
  end

  it "fails the baseline when the filter leaves no test to run" do
    Dir.mktmpdir("kimera-filtered") do |root|
      project(root, false)
      test_run(cwd: root, arguments: ["--no-progress"]) do |output, report, status|
        expect([report, status]).to(eq([nil, 1]), output)
        expect(output).to(include("baseline has no tests to run: 1 test file(s) loaded"))
      end
    end
  end
end
