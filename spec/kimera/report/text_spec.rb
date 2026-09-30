# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/report/text"
require "kimera/results/run_report"
require "stringio"

RSpec.describe(Kimera::Report::Text) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      class Calc
        def a(x, y)
          x <= y
        end
      end
    RUBY
  end

  let(:mutant) { registry.each.find { |m, _| m.label == "<= => <" }.first }

  def listing
    "\n\n1 mutant(s) have no covering test; list them with: " \
      "kimera report rep.json --status no_coverage"
  end

  def instructions
    "1 mutant(s) have no covering test; re-run with --report FILE, " \
      "then `kimera report FILE --status no_coverage` to list them"
  end

  def render(result, **)
    io = StringIO.new
    described_class.new(registry, io: io, color: false).report(Kimera::RunReport.new(results: [result]), **)
    io.string
  end

  def killed
    Kimera::MutantResult.new(mutant_id: mutant.id, status: :killed, file: "calc.rb", duration: 0.1)
  end

  def uncovered
    Kimera::MutantResult.new(mutant_id: mutant.id, status: :no_coverage, file: "calc.rb", duration: 0.0)
  end

  def survivor
    Kimera::MutantResult.new(
      mutant_id: mutant.id, status: :survived, file: "calc.rb", duration: 0.1,
      covering_tests: ["./spec/calc_spec.rb[1:1]"]
    )
  end

  def error
    Kimera::MutantResult.new(
      mutant_id: mutant.id, status: :harness_error, file: "calc.rb",
      detail: "worker crashed before result"
    )
  end

  def diff
    multiline = Kimera::RegistryScan.new.source(<<~RUBY, file: "multi.rb")
      class Multi
        def a(x)
          if x
            :yes
          end
        end
      end
    RUBY
    io = StringIO.new
    described_class.new(multiline, io: io, color: false).report(Kimera::RunReport.new(results: [multiple(multiline)]))
    io.string
  end

  def multiple(multiline)
    Kimera::MutantResult.new(
      mutant_id: multiline.each.find { |entry, _| entry.label == "condition => true" }.first.id,
      status: :survived, file: "multi.rb", duration: 0.1
    )
  end

  it "prints location, original-vs-mutation diff, and covering tests for survivors", :aggregate_failures do
    output = render(survivor)
    expect(output).to(include("survived ##{mutant.id}", "calc.rb:3", "[<= => <]", "- x <= y", "+ x < y"))
    expect(output).to(include("covered by 1 test(s): ./spec/calc_spec.rb[1:1]"))
  end

  it "omits the survivors section when everything is killed", :aggregate_failures do
    output = render(killed)
    expect(output).to(include("killed=1"))
    expect(output).not_to(include("Surviving mutants"))
  end

  it "lists uncovered mutants only when show_no_coverage is set", :aggregate_failures do
    expect(render(uncovered)).not_to(include("Mutants with no covering test"))
    shown = render(uncovered, coverage: :list)
    expect(shown).to(match(/\n\nMutants with no covering test \(1\):/))
    expect(shown).to(include("no coverage ##{mutant.id}", "calc.rb:3", "[<= => <]"))
  end

  # Uncovered mutants are listed only under a --fail-on-no-coverage gate.
  it "points at the survivors subcommand for uncovered mutants when they are not listed", :aggregate_failures do
    expect(render(uncovered, path: "rep.json")).to(include(listing))
    expect(render(uncovered)).to(include(instructions))
    expect(render(uncovered, coverage: :list)).not_to(include("list them with"))
    expect(render(killed)).not_to(include("no covering test"))
  end

  it "indents continuation lines of a multiline diff under the marker", :aggregate_failures do
    output = diff
    expect(output).to(include("    - if x\n            :yes\n          end\n"))
    expect(output).to(include("    + if true\n        :yes\n      end\n"))
  end

  it "omits the no-coverage section when show_no_coverage is set but nothing is uncovered" do
    output = render(killed, coverage: :list)
    expect(output).not_to(include("Mutants with no covering test"))
  end

  # Staying silent about unjudged mutants would read like a clean run.
  it "always lists mutants the harness could not judge, with the reason", :aggregate_failures do
    output = render(error)
    expect(output).to(match(/\n\nMutants Kimera could not judge \(1\):/))
    expect(output).to(include("unjudged ##{mutant.id}", "calc.rb:3", "worker crashed before result", "unjudged=1"))
  end

  it "falls back to the result's own file for an unjudged mutant off-registry" do
    orphan = Kimera::MutantResult.new(
      mutant_id: 999_999, status: :harness_error, file: "gone.rb",
      detail: "worker crashed before result"
    )
    expect(render(orphan)).to(include("unjudged #999999  gone.rb"))
  end

  def rejudged(result)
    result.tap { |judged| judged.note = "judged in a fresh isolated mirror; the warm pass could not: t1" }
  end

  def rendered(results)
    io = StringIO.new
    described_class.new(registry, io: io, color: false).report(Kimera::RunReport.new(results: results))
    io.string
  end

  it "keeps the warm detail as a note under a re-judged survivor or unjudged mutant", :aggregate_failures do
    note = "\n    note: judged in a fresh isolated mirror; the warm pass could not: t1\n"
    expect(render(rejudged(survivor))).to(include("covered by 1 test(s): ./spec/calc_spec.rb[1:1]#{note}"))
    expect(render(rejudged(error))).to(include("worker crashed before result#{note}"))
    expect(render(survivor)).not_to(include("note:"))
  end

  it "tallies the mutants judged again in fresh mirrors, killed ones included" do
    output = rendered([rejudged(killed), rejudged(error), rejudged(killed), survivor])
    tally = "3 mutant(s) the warm pass could not judge, judged again in fresh mirrors: 2 killed, 1 unjudged."
    expect(output).to(include("\n\n#{tally}\n"))
  end

  it "omits the tally when nothing was judged again" do
    expect(render(killed)).not_to(include("judged again"))
  end

  it "omits the unjudged section when every mutant got a verdict" do
    expect(render(killed)).not_to(include("could not judge"))
  end

  it "skips an uncovered result whose mutant is not in the registry", :aggregate_failures do
    orphan = Kimera::MutantResult.new(mutant_id: 999_999, status: :no_coverage, file: "x.rb", duration: 0.0)
    output = render(orphan, coverage: :list)
    expect(output).to(include("Mutants with no covering test (1):"))
    expect(output).not_to(include("#999999"))
  end

  def waived(status, index) = Kimera::MutantResult.new(mutant_id: 100 + index, status: status, file: "calc.rb").waive

  def waivers(path: nil)
    results = %i[killed survived no_coverage timeout].each_with_index.map { |status, index| waived(status, index) }
    io = StringIO.new
    report = Kimera::RunReport.new(results: results + [Kimera::MutantResult.waived(200, "calc.rb")])
    described_class.new(registry, io: io, color: false).report(report, path: path)
    io.string
  end

  it "tallies evaluated ignored mutants by verdict and points at pruning", :aggregate_failures do
    expect(waivers).to(
      include(
        "\n\n2 ignored mutant(s) are now killed (their entries can be pruned); 1 still survive; " \
          "1 could not be judged.\n",
        "2 ignored mutant(s) now killed: rerun with --report FILE, then `kimera baseline prune`"
      )
    )
    expect(waivers(path: "rep.json")).to(
      include("2 ignored mutant(s) now killed: `kimera baseline prune BASELINE.yml --report rep.json`")
    )
  end

  it "stays silent about ignored mutants that were not evaluated" do
    expect(render(Kimera::MutantResult.waived(mutant.id, "calc.rb"))).not_to(include("ignored mutant(s)"))
  end
end
