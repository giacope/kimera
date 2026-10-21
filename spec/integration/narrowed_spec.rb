# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# A run narrowed with --tests cannot know whether a test it left out covers a
# mutant, so its uncovered mutants are reported as such and neither scored as
# not killed nor gated on, unless --fail-on-no-coverage asks for that.
RSpec.describe("kimera run narrowed with --tests (end-to-end)", :aggregate_failures) do
  def files = {
    "app/a.rb" => "class A\n  def big?(n) = n > 9\nend\n",
    "app/b.rb" => "class B\n  def small?(n) = n < 2\nend\n",
    "spec/a_spec.rb" => <<~RUBY,
      require_relative "../app/a"
      RSpec.describe A do
        it("is big at ten") { expect(A.new.big?(10)).to be(true) }
        it("is not big at nine") { expect(A.new.big?(9)).to be(false) }
      end
    RUBY
    "spec/b_spec.rb" => <<~RUBY
      require_relative "../app/b"
      RSpec.describe B do
        it("is small at one") { expect(B.new.small?(1)).to be(true) }
        it("is not small at two") { expect(B.new.small?(2)).to be(false) }
      end
    RUBY
  }

  def narrowed(*flags)
    Dir.mktmpdir("kimera-narrowed") do |root|
      files.each do |path, body|
        FileUtils.mkdir_p(File.dirname(File.join(root, path))) && File.write(File.join(root, path), body)
      end
      test_run(cwd: root, tests: "spec/a_spec.rb", arguments: ["--no-progress", *flags]) do |output, report, status|
        expect(report).not_to(be_nil, output)
        return [output, report, status]
      end
    end
  end

  it "reports what the narrowed tests leave uncovered without scoring or gating on it" do
    output, report, status = narrowed
    uncovered = report.fetch("results").select { |row| row["status"] == "no_coverage" }
    expect(uncovered.map { |row| row["file"] }.uniq).to(eq(["app/b.rb"]))
    expect(uncovered.map { |row| row["detail"] }.uniq).to(eq([Kimera::CLI::Run::Cycle::NARROWED]))
    expect(report.fetch("mutation_score")).to(eq(1.0))
    expect(output).not_to(include("gate failed"))
    expect(status).to(eq(0), output)
  end

  it "still gates on them when --fail-on-no-coverage asks" do
    output, _report, status = narrowed("--fail-on-no-coverage")
    expect(output).to(include("with no covering test (--fail-on-no-coverage)"))
    expect(status).to(eq(2))
  end
end
