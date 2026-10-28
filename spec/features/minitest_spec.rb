# frozen_string_literal: true

RSpec.describe("kimera run with the Minitest adapter") do
  def minitest
    File.join(test_repository_root, "examples", "minitest_app")
  end

  it "drives a Minitest suite, killing caught mutants and reporting the survivor", :aggregate_failures do
    run = test_outcome(cwd: minitest, tests: "test/**/*_test.rb", arguments: ["--framework", "minitest"])
    expect(run.counts.slice("total", "killed", "survived", "error", "timeout", "no_coverage")).to(
      eq("total" => 15, "killed" => 14, "survived" => 1, "error" => 0, "timeout" => 0, "no_coverage" => 0), run.output
    )
    expect([run.verdicts.key("survived"), run.status]).to(eq([14, 2]))
  end

  # R6B3-M1: Rake::TestTask runs `ruby -w` by default; mechanize asserts on a
  # deprecation it prints only `if $VERBOSE`, green under `rake test`, so the
  # baseline kimera ran without -w was red.
  def warned = {
    "Rakefile" => "require \"rake/testtask\"\nRake::TestTask.new { |t| t.pattern = \"test/*_test.rb\" }\n",
    "app/legacy.rb" => <<~RUBY,
      class Legacy
        def self.parse(text)
          warn("Legacy.parse is deprecated") if $VERBOSE
          text.split(",")
        end
      end
    RUBY
    "test/legacy_test.rb" => <<~RUBY
      require "minitest/autorun"
      require_relative "../app/legacy"

      class LegacyTest < Minitest::Test
        def test_parse_warns
          assert_output("", /deprecated/) { assert_equal(%w[a b], Legacy.parse("a,b")) }
        end
      end
    RUBY
  }

  def judged
    test_tree(warned, "kimera-warned") do |root|
      test_outcome(cwd: root, tests: "test/**/*_test.rb", arguments: ["--framework", "minitest", "--no-gate"])
    end
  end

  it "runs the suite with warnings on, as the Rakefile's test task does", :aggregate_failures do
    run = judged
    expect(run.output).not_to(include("not green"))
    expect(run.results.map { |row| [row["mutated"], row["status"]] }).to(
      contain_exactly(
        ["(statement deleted)", "killed"], ["(statement deleted)", "killed"],
        ["warn(\"Legacy.parse is deprecated\") if false", "killed"],
        ["warn(\"Legacy.parse is deprecated\") if true", "survived"]
      )
    )
  end
end
