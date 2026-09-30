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
    [out.string, Kimera::CLI.start(["survivors", *argv])]
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
    absent = %w[operator: label: duration: detail: note: covering failing +]
    absent.each { |a| expect(out).not_to(include(a)) }
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

  it "fails cleanly without a report file" do
    expect do
      _, status = run
      expect(status).to(eq(1))
    end.to(output(/report file is required/).to_stderr)
  end

  it "fails cleanly for a missing report path" do
    expect do
      _, status = run("nope.json")
      expect(status).to(eq(1))
    end.to(output(/no such report/).to_stderr)
  end
end
