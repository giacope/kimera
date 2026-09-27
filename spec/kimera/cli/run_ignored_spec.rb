# frozen_string_literal: true

require "json"
require "kimera/cli/run"
require "kimera/registry/builder"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run, :aggregate_failures) do
  around do |example|
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  end

  let(:out) { StringIO.new }
  let(:errors) { StringIO.new }
  let(:cli) { described_class.new(io: out, errors: errors) }

  def configure
    File.write("calc.rb", "def m(a, b)\n  a > b\nend\n\ndef n(a, b)\n  a < b\nend\n")
    File.write("debt.yml", YAML.dump("ignore" => [rule("> => >=", "accepted debt")]))
    File.write("custom.yml", YAML.dump("baseline" => "debt.yml", "ignore" => [rule("> => <", "equivalent")]))
  end

  def rule(label, reason) = { "file" => "calc.rb", "line" => 2, "label" => label, "reason" => reason }

  def harness(status)
    runner = instance_double(Kimera::CLI::Run::Pass)
    allow(runner).to(receive(:call) { |ids, session| session.merge!(judged(ids, status)) })
    allow(Kimera::CLI::Run::Pass).to(receive(:new).and_return(runner))
    allow(Kimera::Frameworks::Adapter).to(receive(:load).and_return(nil))
    runner
  end

  def judged(ids, status)
    Kimera::RunReport.new(results: ids.map { |id| Kimera::MutantResult.new(mutant_id: id, status: status) })
  end

  def run(*flags)
    [
      cli.run(["calc.rb", "--config", "custom.yml", "--report", "report.json", "--no-color", *flags]),
      JSON.parse(File.read("report.json"))
    ]
  end

  def rows(document, status) = document["results"].select { |row| row["status"] == status }

  def evaluated(ids) = have_received(:call).with(match_array(ids), anything)

  def mutants = Kimera::RegistryScan.new.source(File.read("calc.rb"), file: "calc.rb").each.to_a

  def ids(*labels) = mutants.filter_map { |mutant, _point| mutant.id if labels.include?(mutant.label) }

  it "skips ignored mutants by default, including the baseline's" do
    configure
    runner = harness(:killed)
    status, document = run
    expect(status).to(eq(0))
    expect(runner).to(evaluated(ids("< => <=", "< => >")))
    expect(rows(document, "ignored").map { |row| row["detail"] }).to(all(eq("marked equivalent (ignored)")))
    expect(out.string).to(include("Ignoring 2 mutant(s) marked equivalent."))
    expect(out.string).not_to(include("Evaluating them anyway", "are now killed"))
  end

  it "evaluates ignored mutants with --evaluate-ignored, keeping them ignored with their verdict" do
    configure
    runner = harness(:killed)
    status, document = run("--evaluate-ignored", "--max-ignored", "2")
    expect(status).to(eq(0))
    expect(runner).to(evaluated(mutants.map { |mutant, _point| mutant.id }))
    expect(rows(document, "ignored").map { |row| row.slice("verdict", "detail") })
      .to(all(eq("verdict" => "killed", "detail" => "ignored (killed)")))
    expect(document["counts"]).to(include("ignored" => 2, "killed" => 2))
    expect(out.string).to(include("Evaluating them anyway (--evaluate-ignored)"))
    expect(out.string).to(include("2 ignored mutant(s) are now killed (their entries can be pruned); 0 still survive."))
  end

  it "never gates an evaluated ignored survivor as a survivor, but still budgets it" do
    configure
    harness(:survived)
    expect(run("--evaluate-ignored", "--max-ignored", "2", "--max-survivors", "2").first).to(eq(0))
    expect(run("--evaluate-ignored", "--max-ignored", "1", "--max-survivors", "2").first).to(eq(2))
    expect(errors.string).to(include("ignored=2 > max_ignored=1"))
    expect(out.string).to(include("0 ignored mutant(s) are now killed (their entries can be pruned); 2 still survive."))
  end

  it "judges the baseline's mutants like any other with --no-baseline" do
    configure
    runner = harness(:survived)
    status, document = run("--no-baseline")
    expect(status).to(eq(2))
    expect(runner).to(evaluated(ids("< => <=", "< => >", "> => >=")))
    expect(rows(document, "survived").size).to(eq(3))
    expect(out.string).to(include("Ignoring 1 mutant(s) marked equivalent."))
  end

  it "re-anchors a drifted ignore entry that still singles out one mutant" do
    configure
    File.write("calc.rb", "\n#{File.read("calc.rb")}")
    harness(:killed)
    _status, document = run
    expect(rows(document, "ignored").size).to(eq(2))
    expect(errors.string).to(include("kimera: warning: ignore entry re-anchored: calc.rb:2 → 3 [> => <]"))
    expect(errors.string).not_to(include("stale anchor"))
  end

  it "says nothing about evaluating ignored mutants when none are ignored" do
    Kimera::CLI::Run::Digest.new(io: out, emission: nil).evaluating([])
    expect(out.string).to(eq(""))
  end

  it "keeps the raw baseline entries out of the parsed options" do
    configure
    expect(cli.__send__(:parse, ["--config", "custom.yml"])).not_to(have_key(:baseline_ignore))
    expect(cli.__send__(:parse, ["--config", "custom.yml", "--evaluate-ignored"])[:evaluate_ignored]).to(be(true))
  end

  it "records the --since ref in the report's run provenance" do
    configure
    harness(:killed)
    expect(run.last.dig("run", "since")).to(be_nil)
    expect(run.last["run"]).to(have_key("since"))
  end
end
