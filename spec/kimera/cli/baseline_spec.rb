# frozen_string_literal: true

require "json"
require "kimera/cli"
require "kimera/cli/baseline"
require "stringio"
require "tmpdir"
require "yaml"

RSpec.describe(Kimera::CLI::Baseline, :aggregate_failures) do
  around do |example|
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  end

  let(:out) { StringIO.new }
  let(:errors) { StringIO.new }
  let(:cli) { described_class.new(io: out, errors: errors) }

  def entry(file, line, label, **extra)
    { "file" => file, "line" => line, "label" => label, **extra, "reason" => "debt" }
  end

  def row(line, label, status, verdict = nil, file: "app/a.rb", original: "x")
    { "file" => file, "line" => line, "label" => label, "status" => status, "original" => original }
      .merge(verdict ? { "verdict" => verdict } : {})
  end

  def entries
    [
      entry("app/a.rb", 3, "> => >=", "original" => "x  >\n y"), entry("app/a.rb", 5, "< => <="),
      entry("app/a.rb", 7, "== => !="), entry("app/a.rb", 9, "+ => -"), entry("app/b.rb", 1, "> => <"),
      entry("app/a.rb", 11, "!x => x"), entry("app/a.rb", 13, "&& => ||")
    ]
  end

  def rows
    [
      row(3, "> => >=", "ignored", "killed", original: "x > y"), row(5, "< => <=", "ignored", "survived"),
      row(7, "== => !=", "no_coverage"), row(9, "- => +", "killed"), row(12, "!x => x", "ignored", "survived"),
      row(13, "&& => ||", "ignored")
    ]
  end

  def seed(run: {}, ignore: entries)
    File.write("base.yml", YAML.dump("format_version" => 1, "ignore" => ignore))
    File.write("r.json", JSON.generate("run" => run, "results" => rows))
  end

  def kept = YAML.safe_load_file("base.yml")

  it "sorts every entry by what the report says about its mutant" do
    seed
    expect(cli.run(%w[review base.yml --report r.json])).to(eq(0))
    expect(out.string).to(
      include(
        "7 accepted mutant(s) in base.yml, judged against r.json:",
        "\nKilled, safe to prune (1):\n  app/a.rb:3 [> => >=] (killed) — debt\n",
        "\nStill surviving (2):\n  app/a.rb:5 [< => <=] (survived) — debt\n  app/a.rb:11 → 12 [!x => x] (survived)",
        "\nUnjudged (no verdict in this report) (2):\n  app/a.rb:7 [== => !=] (no_coverage) — debt\n",
        "  app/a.rb:13 [&& => ||] (ignored) — debt\n",
        "\nStale: the report covers the file, but no mutant matches (1):\n  app/a.rb:9 [+ => -] — debt\n",
        "\nNot in the report's scope (1):\n  app/b.rb:1 [> => <] — debt\n"
      )
    )
    expect(out.string).to(
      end_with(
        "\n1 entr(ies) were not evaluated: rerun with `kimera run --evaluate-ignored --report FILE`\n" \
          "\nPrune 2 entr(ies): kimera baseline prune base.yml --report r.json\n"
      )
    )
  end

  it "prunes killed and stale entries, re-anchors drifted ones, and keeps the rest in order" do
    seed
    expect(cli.run(%w[prune base.yml --report r.json])).to(eq(0))
    expect(kept["format_version"]).to(eq(1))
    expect(kept["ignore"].map { |fields| fields.values_at("file", "line") }).to(
      eq([["app/a.rb", 5], ["app/a.rb", 7], ["app/b.rb", 1], ["app/a.rb", 12], ["app/a.rb", 13]])
    )
    expect(out.string).to(
      eq(
        "Removed 2 entr(ies) from base.yml:\n  - app/a.rb:3 [> => >=] (killed)\n  - app/a.rb:9 [+ => -] (stale)\n" \
          "Re-anchored 1 entr(ies) to their mutant's current line:\n  app/a.rb:11 → 12 [!x => x]\n" \
          "base.yml now holds 5 accepted mutant(s) (was 7); max_ignored can be lowered by 2.\n"
      )
    )
  end

  it "leaves the file alone on a dry run, or when nothing changed" do
    seed
    before = File.read("base.yml")
    expect(cli.run(%w[prune base.yml --report r.json --dry-run])).to(eq(0))
    expect(File.read("base.yml")).to(eq(before))
    expect(out.string).to(include("Would remove 2 entr(ies)", "would hold 5", "(dry run: base.yml is unchanged)"))
    File.write("base.yml", "# reviewed in #42\n#{YAML.dump("ignore" => [entry("app/a.rb", 5, "< => <=")])}")
    expect(cli.run(%w[prune base.yml --report r.json])).to(eq(0))
    expect(out.string).to(end_with("Nothing to prune: base.yml keeps its 1 accepted mutant(s).\n"))
    expect(File.read("base.yml")).to(start_with("# reviewed in #42\n"))
  end

  def pruned(*ignore)
    seed(ignore: ignore)
    out.string = +""
    cli.run(%w[prune base.yml --report r.json])
    [out.string, kept["ignore"]]
  end

  it "reports only the kind of change it made" do
    removed, left = pruned(entry("app/a.rb", 3, "> => >="), entry("app/a.rb", 5, "< => <="))
    expect(removed).not_to(include("Re-anchored"))
    expect(left).to(eq([entry("app/a.rb", 5, "< => <=")]))
    moved, left = pruned(entry("app/a.rb", 11, "!x => x"))
    expect(moved).not_to(include("Removed"))
    expect(moved).to(include("max_ignored can be lowered by 0."))
    expect(left).to(eq([entry("app/a.rb", 12, "!x => x")]))
  end

  it "only re-anchors an entry to its sole drifted mutant" do
    seed(ignore: [entry("app/a.rb", 1, "!x => x"), entry("app/*.rb", 1, "&& => ||", "original" => "y")])
    cli.run(%w[prune base.yml --report r.json])
    expect(kept["ignore"]).to(eq([entry("app/a.rb", 12, "!x => x")]))
  end

  it "treats a missing mutant as out of scope in an incremental report" do
    seed(run: { "since" => "origin/main" })
    cli.run(%w[prune base.yml --report r.json])
    expect(kept["ignore"].size).to(eq(6))
    expect(out.string).to(include("max_ignored can be lowered by 1."))
  end

  def verdicts(*statuses)
    File.write("base.yml", YAML.dump("ignore" => [{ "file" => "app/c.rb", "label" => "x", "reason" => "debt" }]))
    judged = statuses.map { |status| { "file" => "app/c.rb", "line" => 1, "label" => "x", "status" => status } }
    File.write("r.json", JSON.generate("results" => judged))
    out.string = +""
    cli.run(%w[review base.yml --report r.json])
    out.string
  end

  it "rates an entry matching several mutants by its weakest verdict" do
    expect(verdicts("killed", "timeout").lines[2]).to(start_with("Killed"))
    surviving = verdicts("killed", "survived", "no_coverage")
    expect(surviving.lines[2]).to(start_with("Still surviving"))
    expect(surviving).not_to(include("Prune", "not evaluated"))
    expect(verdicts("killed", "no_coverage").lines[2]).to(start_with("Unjudged"))
  end

  it "rejects a prune or review it cannot carry out" do
    seed
    expect(cli.run(%w[prune base.yml])).to(eq(1))
    expect(cli.run(%w[prune base.yml --report missing.json])).to(eq(1))
    expect(cli.run(%w[review missing.yml --report r.json])).to(eq(1))
    expect(cli.run(%w[review base.yml extra])).to(eq(1))
    expect(errors.string.lines).to(
      eq(
        [
          "kimera: baseline prune needs --report FILE\n", "kimera: no such report: missing.json\n",
          "kimera: no such baseline: missing.yml\n",
          "kimera: Usage: kimera baseline review BASELINE.yml [--report REPORT.json]\n"
        ]
      )
    )
  end

  it "records each survivor's original snippet in a new baseline, when the report has it" do
    survivors = [row(20, "> => <", "survived", original: "a > b"), row(21, "> => <", "survived").except("original")]
    File.write("r.json", JSON.generate("results" => rows + survivors))
    cli.run(%w[create r.json --reason debt --output base.yml])
    expect(kept["ignore"].last).to(eq(entry("app/a.rb", 21, "> => <")))
    expect(kept["ignore"].first.keys).to(eq(%w[file line label original reason]))
  end

  it "matches on the anchors a report row carries, skipping the rest" do
    seed(ignore: [entry("app/a.rb", 3, "> => >=", "method" => "m", "column" => 4)])
    cli.run(%w[review base.yml --report r.json])
    expect(out.string).to(include("Killed, safe to prune (1):"))
  end
end
