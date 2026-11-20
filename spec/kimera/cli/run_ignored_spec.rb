# frozen_string_literal: true

require "json"
require "kimera/cli/run"
require "kimera/registry/builder"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run, :aggregate_failures) do
  def inside
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        configure
        yield
      end
    end
  end

  let(:out) { StringIO.new }
  let(:errors) { StringIO.new }
  let(:cli) { described_class.new(io: out, errors: errors) }
  let(:runner) { harness(:killed) }

  def configure
    File.write("calc.rb", "def m(a, b)\n  a > b\nend\n\ndef n(a, b)\n  a < b\nend\n")
    FileUtils.mkdir_p("spec")
    File.write("spec/calc_spec.rb", "")
    File.write("debt.yml", YAML.dump("ignore" => [rule("> => >=", "accepted debt")]))
    File.write("custom.yml", YAML.dump("baseline" => "debt.yml", "ignore" => [rule("> => <", "equivalent")]))
  end

  def rule(label, reason) = { "file" => "calc.rb", "line" => 2, "label" => label, "reason" => reason }

  def harness(status) = FakeHarness.new { |ids| judged(ids, status) }

  def judged(ids, status)
    Kimera::RunReport.new(results: ids.map { |id| Kimera::MutantResult.new(mutant_id: id, status: status) })
  end

  def run(*flags, judge: runner)
    judging = described_class.new(io: out, errors: errors, bench: FakeBench.new(harness: judge))
    outcome = judging.run(["calc.rb", "--config", "custom.yml", "--report", "report.json", "--no-color", *flags])
    [ended(outcome, out, errors), JSON.parse(File.read("report.json"))]
  end

  def rows(document, status) = document["results"].select { |row| row["status"] == status }

  def evaluated(ids) = satisfy { |judge| ran(judge).sort == ids.sort }

  def ran(judge) = judge.asked.filter_map { |kind, run| run if kind == :run }.flatten

  def mutants = Kimera::RegistryScan.new.source(File.read("calc.rb"), file: "calc.rb").each.to_a

  def ids(*labels) = mutants.filter_map { |mutant, _point| mutant.to_i if labels.include?(mutant.to_s) }

  describe "by default" do
    it "skips ignored mutants, including the baseline's" do
      inside do
        status, = run
        expect(status).to(eq(0))
        expect(runner).to(evaluated(ids("< => <=", "< => >")))
      end
    end

    it "reports them ignored as marked equivalent" do
      _, document = inside { run }
      expect(rows(document, "ignored").map { |row| row["detail"] }).to(all(eq("marked equivalent (ignored)")))
      expect(out.string).to(include("Ignoring 2 mutant(s) marked equivalent."))
      expect(out.string).not_to(include("Evaluating them anyway", "are now killed"))
    end
  end

  describe "with --evaluate-ignored" do
    def evaluating = run("--evaluate-ignored", "--max-ignored", "2")

    it "evaluates ignored mutants" do
      inside do
        expect(evaluating.first).to(eq(0))
        expect(runner).to(evaluated(mutants.map { |mutant, _point| mutant.to_i }))
      end
    end

    it "keeps them ignored, with their verdict" do
      inside do
        document = evaluating.last
        expect(rows(document, "ignored").map { |row| row.slice("verdict", "detail") })
          .to(all(eq("verdict" => "killed", "detail" => "ignored (killed)")))
        expect(document["counts"]).to(include("ignored" => 2, "killed" => 2))
      end
    end

    it "says it evaluates them, and which are now killed" do
      inside do
        evaluating
        expect(out.string).to(
          include(
            "Evaluating them anyway (--evaluate-ignored)",
            "2 ignored mutant(s) are now killed (their entries can be pruned); 0 still survive."
          )
        )
      end
    end
  end

  it "never gates an evaluated ignored survivor as a survivor" do
    flags = ["--evaluate-ignored", "--max-ignored", "2", "--max-survivors", "2"]
    inside { expect(run(*flags, judge: harness(:survived)).first).to(eq(0)) }
    expect(out.string).to(include("0 ignored mutant(s) are now killed (their entries can be pruned); 2 still survive."))
  end

  it "still budgets an evaluated ignored survivor" do
    inside do
      flags = ["--evaluate-ignored", "--max-ignored", "1", "--max-survivors", "2"]
      expect(run(*flags, judge: harness(:survived)).first).to(eq(2))
      expect(errors.string).to(include("ignored=2 > max_ignored=1"))
    end
  end

  it "judges the baseline's mutants like any other with --no-baseline" do
    runner = harness(:survived)
    (status, document), expected = inside { [run("--no-baseline", judge: runner), ids("< => <=", "< => >", "> => >=")] }
    expect([status, rows(document, "survived").size]).to(eq([2, 3]))
    expect(runner).to(evaluated(expected))
    expect(out.string).to(include("Ignoring 1 mutant(s) marked equivalent."))
  end

  def drifted
    File.write("calc.rb", "\n#{File.read("calc.rb")}")
    run.last
  end

  it "re-anchors a drifted ignore entry that still singles out one mutant" do
    expect(rows(inside { drifted }, "ignored").size).to(eq(2))
    expect(errors.string).to(include("kimera: warning: ignore entry re-anchored: calc.rb:2 → 3 [> => <]"))
    expect(errors.string).not_to(include("stale anchor"))
  end

  it "says nothing about evaluating ignored mutants when none are ignored" do
    inside do
      Kimera::CLI::Run::Digest.new(io: out, emission: nil).evaluating([])
      expect(out.string).to(eq(""))
    end
  end

  it "keeps the raw baseline entries out of the parsed options" do
    inside do
      parser = Kimera::CLI::Run::Arguments.new
      expect(parser.parse(["--config", "custom.yml"]).to_h).not_to(have_key(:baseline_ignore))
      expect(parser.parse(["--config", "custom.yml", "--evaluate-ignored"])[:evaluate_ignored]).to(be(true))
    end
  end

  it "records the --since ref in the report's run provenance" do
    inside do
      expect(run.last.dig("run", "since")).to(be_nil)
      expect(run.last["run"]).to(have_key("since"))
    end
  end
end
