# frozen_string_literal: true

# A run-once guard: whichever lexer test runs first readies Sql for the rest
# of the process, so with the superclass call gone the Hql test still passes
# after the Sql test. Alone in a fresh process it fails.
RSpec.describe("kimera run confirming survivors (end-to-end)", :aggregate_failures) do
  def files = {
    "lib/lexer.rb" => <<~RUBY,
      class Lexer
        def self.ready!
          return if @ready
          @ready = true
          superclass.ready! unless superclass == Lexer
          setup
        end

        def self.setup; end
      end

      class Sql < Lexer
        def self.setup = const_set(:KEYWORDS, %w[select])
        def self.keywords = self::KEYWORDS
      end

      class Hql < Sql
        def self.setup; end
      end
    RUBY
    "test/lexer_test.rb" => <<~RUBY
      require "minitest/autorun"
      require_relative "../lib/lexer"

      class SqlTest < Minitest::Test
        def test_sql_keywords
          Sql.ready!
          assert_equal %w[select], Sql.keywords
        end
      end

      class HqlTest < Minitest::Test
        def test_hql_inherits_keywords
          sleep 0.2
          Hql.ready!
          assert_equal %w[select], Hql.keywords
        end
      end
    RUBY
  }

  def run_lexer(*flags)
    arguments = ["--framework", "minitest", "--no-progress", "lib/lexer.rb", *flags]
    test_tree(files, "kimera-masked") do |root|
      test_outcome(cwd: root, tests: "test/**/*_test.rb", arguments: arguments)
    end
  end

  # What the confirming run says about the mutants the plain run let survive.
  def confirmation(run, masked)
    {
      statuses: run.verdicts.values.uniq,
      confirmed: run.report&.dig("run", "confirm_survivors"),
      details: run.results.filter_map { |row| row["detail"] if masked.include?(row["mutant_id"]) }
    }
  end

  it "kills what an earlier test masked once each covering test runs alone" do
    plain = run_lexer
    masked = plain.verdicts.select { |_id, status| status == "survived" }.keys
    expect(masked).not_to(be_empty, plain.output)
    expect(confirmation(run_lexer("--confirm-survivors"), masked)).to(
      match(statuses: ["killed"], confirmed: true, details: include(start_with("failed alone in a fresh process")))
    )
  end
end
