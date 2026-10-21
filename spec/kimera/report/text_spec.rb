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
    "1 mutant(s) have no covering test; run without --no-report, " \
      "then `kimera report --status no_coverage` to list them"
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
    expect(output).to(include("covered by 1 test(s):\n      ./spec/calc_spec.rb[1:1]\n"))
  end

  it "lists the mutants only other units' tests reach, with those tests and why", :aggregate_failures do
    unowned = survivor.dup.tap { |result| result.status = :uncovered_by_unit }.tap { |result| result.detail = "why" }
    out = render(unowned)
    expect(out).to(
      include(
        "Reached only by other units' tests (1):\n\n  " \
          "uncovered_by_unit ##{mutant.id}  calc.rb:3:5  in a  [<= => <]\n    " \
          "- x <= y\n    + x < y\n    covered by 1 test(s):\n      ./spec/calc_spec.rb[1:1]\n    why\n"
      )
    )
    expect(out).not_to(include("Surviving mutants"))
    expect(render(survivor)).not_to(include("Reached only"))
  end

  def flaky(found)
    io = StringIO.new
    report = Kimera::RunReport.new(
      results: [killed],
      tests: { "t1" => { "name" => "one", "location" => "a_spec.rb:3" } }
    )
    described_class.new(registry, io: io, color: false).report(report.annotate(flaky: found))
    io.string
  end

  it "names each flaky test, how often and under which seeds it failed, and why", :aggregate_failures do
    flake = { "test" => "t1", "failed_runs" => 2, "seeds" => [8, 9], "failure" => "\nExpected 0\n  got 1" }
    out = flaky("runs" => 2, "seeds" => [8, 9], "tests" => 3, "flaky" => [flake])
    expect(out).to(
      include(
        "\n\nFlaky tests (1), in 2 rerun(s) of 3 covering test(s), seeds 8, 9:\n  " \
          "a_spec.rb:3  one  failed 2 (seed 8, 9): Expected 0\n  " \
          "Each passed the baseline but failed a rerun, so it kills no mutant.\n"
      )
    )
    expect(flaky("runs" => 1, "seeds" => [8], "tests" => 1, "flaky" => [flake.merge("failure" => "")]))
      .to(include("  a_spec.rb:3  one  failed 2 (seed 8, 9): no message\n"))
  end

  def judged(suite)
    io = StringIO.new
    counted =
      killed.tap do |result|
        result.covering_tests = %w[t1 t2]
      end.tap { |result| result.killing_tests = %w[t1 t2] }
    report = Kimera::RunReport.new(
      results: [counted],
      tests: { "t1" => { "name" => "one", "location" => "a_spec.rb:3" } }
    )
    described_class.new(registry, io: io, color: false).report(report.annotate(suite: suite))
    io.string
  end

  it "sums up test quality and names the tests that kill nothing or only what others kill", :aggregate_failures do
    out = judged(%w[t1 t2 t3])
    expect(out).to(
      include(
        "\nTest quality (3 tests):\n  0 kill none of the mutants they cover; 2 are redundant " \
          "(another test kills each mutant they kill); 1 cover no mutant in scope.\n  " \
          "Redundant:\n    a_spec.rb:3  one\n    t2\n"
      )
    )
    expect(out).not_to(include("Kill nothing", "more;"))
    expect(render(killed)).not_to(include("Test quality"))
  end

  it "names at most ten tests of each kind, pointing at the JSON report for the rest", :aggregate_failures do
    idle = Array.new(12) { |index| "idle#{index}" }
    many = killed.tap { |result| result.covering_tests = idle }.tap { |result| result.killing_tests = [] }
    io = StringIO.new
    described_class.new(
      registry, io: io,
      color: false
    ).report(Kimera::RunReport.new(results: [many]).annotate(suite: idle))
    expect(io.string).to(include("  Kill nothing:\n    idle0\n"))
    expect(io.string).to(include("    idle9\n    (+2 more; the JSON report's test_quality lists them all)\n"))
    expect(io.string).not_to(include("idle10"))
  end

  it "says when the reruns found no flaky test, and nothing when none ran", :aggregate_failures do
    none = flaky("runs" => 1, "seeds" => [8], "tests" => 4, "flaky" => [])
    expect(none).to(include("\n\nNo flaky tests in 1 rerun(s) of 4 covering test(s), seeds 8.\n"))
    expect(none).not_to(include("Each passed"))
    expect(render(killed)).not_to(include("flaky"))
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

  it "heads a narrowed run's uncovered mutants as not covered by the narrowed tests", :aggregate_failures do
    note = "narrowed run: --tests matched 1 of 2 test files"
    expect(
      render(
        uncovered, coverage: :list,
        scope: note
      )
    ).to(match(/\n\nMutants not covered by the narrowed tests \(1\):/))
    expect(render(uncovered, scope: note)).to(include("1 mutant(s) not covered by the narrowed tests; run without"))
  end

  it "gives the reason under an uncovered mutant that has one", :aggregate_failures do
    reached = uncovered.tap { |result| result.detail = Kimera::MutationPoint::ORDER_REASON }
    expect(render(reached, coverage: :list)).to(include("]\n    #{Kimera::MutationPoint::ORDER_REASON}\n"))
    expect(render(uncovered, coverage: :list)).not_to(include(Kimera::MutationPoint::ORDER_REASON, "]\n    \n"))
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
    expect(output).to(include("    + if true\n            :yes\n          end\n"))
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
    expect(render(rejudged(survivor))).to(include("covered by 1 test(s):\n      ./spec/calc_spec.rb[1:1]#{note}"))
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
    report = Kimera::RunReport.new(results: results + [Kimera::MutantResult.from_waiver(200, "calc.rb")])
    described_class.new(registry, io: io, color: false).report(report, path: path)
    io.string
  end

  it "tallies evaluated ignored mutants by verdict and points at pruning", :aggregate_failures do
    expect(waivers).to(
      include(
        "\n\n2 ignored mutant(s) are now killed (their entries can be pruned); 1 still survive; " \
          "1 could not be judged.\n",
        "2 ignored mutant(s) now killed: run without --no-report, then `kimera baseline prune`"
      )
    )
    expect(waivers(path: "rep.json")).to(
      include("2 ignored mutant(s) now killed: `kimera baseline prune BASELINE.yml --report rep.json`")
    )
  end

  it "stays silent about ignored mutants that were not evaluated" do
    expect(render(Kimera::MutantResult.from_waiver(mutant.id, "calc.rb"))).not_to(include("ignored mutant(s)"))
  end
end
