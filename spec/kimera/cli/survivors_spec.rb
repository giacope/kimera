# frozen_string_literal: true

require "fileutils"
require "json"
require "kimera/cli"
# Required eagerly: a lazy require after the self-host overlay would load the
# original source over the guards.
require "kimera/cli/survivors"
require "tmpdir"

RSpec.describe("kimera survivors", :aggregate_failures) do
  let(:dir) { Dir.mktmpdir }
  let(:report_path) { File.join(dir, "report.json") }
  let(:report) do
    {
      "counts" => { "total" => 3 },
      "results" => [
        {
          "mutant_id" => 7, "status" => "survived", "file" => "app/models/user.rb",
          "line" => 13, "operator" => "statement_deletion",
          "label" => "delete `where(active: true)`",
          "original" => "where(active: true)", "mutated" => "(statement deleted)",
          "covering_tests" => %w[UserTest#test_active UserTest#test_scope],
          "failing_tests" => %w[UserTest#test_active],
          "detail" => "sample detail", "duration" => 0.4, "note" => "judged in a fresh isolated mirror"
        },
        {
          "mutant_id" => 9, "status" => "survived", "file" => "app/models/book.rb",
          "line" => 2, "operator" => "comparison", "label" => "> => >=",
          "original" => "a > b", "mutated" => "a >= b", "covering_tests" => []
        },
        {
          "mutant_id" => 11, "status" => "no_coverage", "file" => "app/models/book.rb",
          "line" => 8, "label" => "condition => true", "original" => "x?"
        },
        # Only the required fields, so optional --id lines can be pinned absent.
        {
          "mutant_id" => 12, "status" => "timeout", "file" => "app/models/bare.rb",
          "original" => "z"
        }
      ]
    }
  end

  before { File.write(report_path, JSON.generate(report)) }
  after { FileUtils.remove_entry(dir) }

  def run(*argv)
    out = StringIO.new
    original = $stdout
    $stdout = out
    [out.string, Kimera::CLI.new.run(["survivors", *argv])]
  ensure
    $stdout = original
  end

  it "lists survivors with location and diff" do
    out, status = run(report_path)
    expect(status).to(eq(0))
    expect(out).to(include("2 survived mutant(s):", "#7  app/models/user.rb:13  [delete `where(active: true)`]"))
    expect(out).to(include("- where(active: true)", "+ (statement deleted)"))
  end

  it "shows the coverage count and sorts survivors by file" do
    out, = run(report_path)
    expect(out).to(include("covered by 2 test(s)"))
    # #9 is in book.rb, #7 in user.rb.
    expect(out.index("#9")).to(be < out.index("#7"))
    expect(out).not_to(include("covered by 0"))
  end

  it "prints the no-mutants line, not an empty section, for a status with none" do
    out, status = run(report_path, "--status", "error")
    expect(status).to(eq(0))
    expect(out).to(eq("no error mutants\n"))

    filtered, = run(report_path, "zzz")
    expect(filtered).to(eq("no survived mutants matching zzz\n"))
  end

  it "omits the + line for a mutant with no mutated source" do
    out, = run(report_path, "--status", "no_coverage")
    expect(out).to(include("- x?"))
    expect(out).not_to(include("+ "))
  end

  it "filters by file substring" do
    out, = run(report_path, "book")
    expect(out).to(include("#9"))
    expect(out).not_to(include("#7"))
  end

  it "lists another status with --status" do
    out, = run(report_path, "--status", "no_coverage")
    expect(out).to(include("1 no_coverage mutant(s):"))
    expect(out).to(include("#11"))
  end

  it "shows one mutant's header and body with --id" do
    out, status = run(report_path, "--id", "7")
    expect(status).to(eq(0))
    expect(out).to(include("#7  survived  app/models/user.rb:13", "operator: statement_deletion"))
    expect(out).to(include("label:    delete `where(active: true)`", "duration: 400ms", "detail:   sample detail"))
    expect(out).to(include("detail:   sample detail\n  note:     judged in a fresh isolated mirror\n"))
  end

  it "shows one mutant's test lists with --id" do
    out, = run(report_path, "--id", "7")
    expect(out).to(include("covering tests (2):", "failing tests (1):", "UserTest#test_active"))
  end

  it "omits the optional lines for a bare result with --id" do
    out, status = run(report_path, "--id", "12")
    expect(status).to(eq(0))
    expect(out).to(include("#12  timeout  app/models/bare.rb", "- z"))
    absent = %w[at: operator: label: duration: detail: note: covering failing +]
    absent.each { |a| expect(out).not_to(include(a)) }
    expect(out).to(eq("#12  timeout  app/models/bare.rb\n  - z\n"))
  end

  describe "multiline diffs" do
    let(:report) do
      {
        "results" => [
          {
            "mutant_id" => 3, "status" => "survived", "file" => "app/x.rb",
            "line" => 4, "label" => "condition => true",
            "original" => "if x\n  :yes\nend", "mutated" => "if true\n  :yes\nend"
          }
        ]
      }
    end

    it "indents continuation lines in the list view" do
      out, = run(report_path)
      expect(out).to(include("    - if x\n        :yes\n      end\n"))
      expect(out).to(include("    + if true\n        :yes\n      end\n"))
    end

    it "indents continuation lines in the --id view" do
      out, = run(report_path, "--id", "3")
      expect(out).to(include("  - if x\n      :yes\n    end\n"))
      expect(out).to(include("  + if true\n      :yes\n    end\n"))
    end
  end

  describe "a report with positions, test names and its source at hand" do
    let(:report) do
      {
        "run" => { "source_root" => dir },
        "tests" => {
          "UserTest#test_active" => { "name" => "UserTest#test_active", "location" => "test/user_test.rb:4" }
        },
        "results" => [
          {
            "mutant_id" => 7, "status" => "killed", "file" => "app/user.rb", "line" => 3, "column" => 5,
            "end_line" => 3, "method" => "active", "label" => "delete", "original" => "where(active: true)",
            "covering_tests" => %w[UserTest#test_active UserTest#test_other],
            "detail" => "Minitest::Assertion: \nExpected true\n\n    test/user_test.rb:5"
          }
        ]
      }
    end

    def source(text)
      FileUtils.mkdir_p(File.join(dir, "app"))
      File.write(File.join(dir, "app/user.rb"), text)
    end

    it "shows where a mutant outside any method sits, naming no method" do
      report["results"].first.delete("method")
      File.write(report_path, JSON.generate(report))
      out, = run(report_path, "--id", "7")
      expect(out).to(include("  at:       app/user.rb:3:5\n"))
    end

    it "shows where the mutant sits and the enclosing method", :aggregate_failures do
      out, = run(report_path, "--id", "7")
      expect(out).to(include("  at:       app/user.rb:3:5  in active\n"))
      listed, = run(report_path, "--status", "killed")
      expect(listed).to(include("#7  app/user.rb:3  in active  [delete]"))
    end

    it "prints the lines around the mutant, marking its own" do
      source("class User\n  def active\n    where(active: true)\n  end\nend\n")
      out, = run(report_path, "--id", "7")
      lines = ["    1 | class User", "    2 |   def active", "  > 3 |     where(active: true)", "    4 |   end"]
      expect(out).to(include(["", *lines, "    5 | end", "", ""].join("\n")))
    end

    it "marks every line a multi-line mutant spans" do
      report["results"].first["end_line"] = 4
      File.write(report_path, JSON.generate(report))
      source("class User\n  def active\n    where(active: true)\n  end\nend\n")
      out, = run(report_path, "--id", "7")
      expect(out).to(include("  > 3 |     where(active: true)\n  > 4 |   end\n"))
    end

    it "marks the mutant's line alone when the report has no end line" do
      report["results"].first.delete("end_line")
      File.write(report_path, JSON.generate(report))
      source("class User\n  def active\n    where(active: true)\n  end\nend\n")
      out, = run(report_path, "--id", "7")
      expect(out).to(include("  > 3 |     where(active: true)\n    4 |   end\n"))
    end

    it "says so instead of printing context when the file has changed since the report", :aggregate_failures do
      source("class User\nend\n")
      out, = run(report_path, "--id", "7")
      expect(out).to(include("  (app/user.rb changed since the report; no source context)\n"))
      expect(out).not_to(include(" | "))
    end

    it "lays a multi-line detail out under its label, without blank lines or trailing spaces" do
      out, = run(report_path, "--id", "7")
      detail = "  detail:   Minitest::Assertion:\n            Expected true\n                test/user_test.rb:5\n"
      expect(out).to(include(detail))
    end

    it "names the tests it knows and lists the rest by id" do
      out, = run(report_path, "--id", "7")
      expect(out).to(include("    test/user_test.rb:4  UserTest#test_active\n    UserTest#test_other\n"))
    end
  end

  describe "line ordering within a file" do
    let(:report) do
      {
        "results" => [
          {
            "mutant_id" => 1, "status" => "survived", "file" => "app/x.rb",
            "line" => 20, "label" => "a", "original" => "a"
          },
          {
            "mutant_id" => 2, "status" => "survived", "file" => "app/x.rb",
            "line" => 5, "label" => "b", "original" => "b"
          },
          {
            "mutant_id" => 3, "status" => "survived", "file" => "app/x.rb",
            "label" => "c", "original" => "c"
          }
        ]
      }
    end

    it "sorts by line, with a line-less result first" do
      out, = run(report_path)
      expect(out.index("#3")).to(be < out.index("#2"))
      expect(out.index("#2")).to(be < out.index("#1"))
    end
  end

  it "fails cleanly for an unreadable report" do
    File.write(report_path, "{ not json")
    expect do
      _, status = run(report_path)
      expect(status).to(eq(1))
      # The parser's own message must follow the colon.
    end.to(output(/unreadable report #{Regexp.escape(report_path)}: \S+/).to_stderr)
  end

  it "fails cleanly for an unknown id" do
    expect do
      _, status = run(report_path, "--id", "999")
      expect(status).to(eq(1))
    end.to(output(/no mutant #999/).to_stderr)
  end

  it "reads the default report when none is named, and says how to make one when it is missing" do
    expect do
      _, status = Dir.chdir(dir) { run }
      expect(status).to(eq(1))
    end.to(output(%r{no such report: tmp/kimera/report\.json \(run kimera run first, or pass REPORT\.json\)}).to_stderr)
  end

  it "reads the default report, taking a lone non-report argument as the file filter", :aggregate_failures do
    FileUtils.mkdir_p(File.join(dir, "tmp/kimera"))
    FileUtils.cp(report_path, File.join(dir, "tmp/kimera/report.json"))
    out, status = Dir.chdir(dir) { run("book") }
    expect(status).to(eq(0))
    expect(out).to(include("#9"))
    expect(out).not_to(include("#7"))
  end

  it "fails cleanly for a missing report path" do
    expect do
      _, status = run("nope.json")
      expect(status).to(eq(1))
    end.to(output(/no such report/).to_stderr)
  end
end
