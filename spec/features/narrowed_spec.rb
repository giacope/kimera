# frozen_string_literal: true

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
    arguments = ["--no-progress", *flags]
    test_tree(files, "kimera-narrowed") do |root|
      test_outcome(cwd: root, tests: "spec/a_spec.rb", arguments: arguments)
    end
  end

  def uncovered(run)
    run.results.select { |row| row["status"] == "no_coverage" }.map { |row| row.slice("file", "detail") }.uniq
  end

  it "reports what the narrowed tests leave uncovered without scoring or gating on it" do
    run = narrowed
    expect(uncovered(run)).to(eq([{ "file" => "app/b.rb", "detail" => Kimera::CLI::Run::Cycle::NARROWED }]), run.output)
    expect([run.report&.fetch("mutation_score"), run.status]).to(eq([1.0, 0]), run.output)
    expect(run.output).not_to(include("gate failed"))
  end

  it "still gates on them when --fail-on-no-coverage asks" do
    run = narrowed("--fail-on-no-coverage")
    expect(run.output).to(include("with no covering test (--fail-on-no-coverage)"))
    expect(run.status).to(eq(2))
  end
end
