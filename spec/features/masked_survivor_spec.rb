# frozen_string_literal: true

require "fileutils"
require "tmpdir"

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

  def project(root)
    files.each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), body)
    end
  end

  def statuses(report) = report.fetch("results").to_h { |row| [row["mutant_id"], row["status"]] }

  def run_lexer(*flags)
    Dir.mktmpdir("kimera-masked") do |root|
      project(root)
      arguments = ["--framework", "minitest", "--no-progress", "lib/lexer.rb", *flags]
      test_run(cwd: root, tests: "test/**/*_test.rb", arguments: arguments) do |output, report, _status|
        expect(report).not_to(be_nil, output)
        return report
      end
    end
  end

  it "kills what an earlier test masked once each covering test runs alone" do
    masked = run_lexer
    expect(statuses(masked).values).to(include("survived"))
    confirmed = run_lexer("--confirm-survivors")
    expect(statuses(confirmed).values.uniq).to(eq(["killed"]))
    expect(confirmed.dig("run", "confirm_survivors")).to(be(true))
    unmasked = confirmed.fetch("results").find { |row| statuses(masked)[row["mutant_id"]] == "survived" }
    expect(unmasked["detail"]).to(start_with("failed alone in a fresh process"))
  end
end
