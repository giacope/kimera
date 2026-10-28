# frozen_string_literal: true

require "kimera/execution/block_use"
require "kimera/execution/isolated"
require "kimera/registry/builder"
require "kimera/report/progress"
require "stringio"
require "tmpdir"

# The warm pass hands over what it could not judge; each mutant is judged
# again in a mirror of its own, and a kill stands only if its tests pass in
# another fresh mirror without the mutant.
RSpec.describe(Kimera::Execution::IsolatedExecution, "#rejudge", :aggregate_failures) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end

  let(:ids) { registry.each.map { |mutant, _point| mutant.id }.first(2) }
  let(:note) { "judged in a fresh isolated mirror; the warm pass could not: warm " }

  def test_bar(sink)
    Class.new do
      define_method(:initialize) { |s| @s = s }
      define_method(:note) { |text| @s << [:note, text] }
      define_method(:start) { |total, label| @s << [:start, total, label] }
      define_method(:tick) { |status| @s << [:tick, status] }
      define_method(:finish) { @s << [:finish] }
    end.new(sink)
  end

  def test_warm(id)
    Kimera::MutantResult.new(mutant_id: id, status: :harness_error, file: "calc.rb", detail: "warm #{id}")
  end

  # Concurrent workers meet before either judges, so each takes a mutant of
  # its own however the threads are scheduled.
  def test_meet(arrived, slot)
    return unless slot
    arrived << slot
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    sleep(0.01) until arrived.size > 1 || Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
  end

  def test_judged(arrived, isolated, trial)
    test_meet(arrived, trial.slot)
    status, detail = isolated.fetch(trial.id)
    Kimera::MutantResult.new(
      mutant_id: trial.id, status: status, file: "calc.rb", covering_tests: ["t#{trial.id}"], detail: detail,
      failing_tests: (["k#{trial.id}"] if status == :killed)
    )
  end

  # isolated: id => [status, detail]; control: the unmutated outcome.
  def test_engine(log, isolated:, control:)
    judged = method(:test_judged).curry[Thread::Queue.new, isolated]
    Class.new(described_class) do
      define_method(:evaluate) do |trial|
        log << [:mutant, trial.id, trial.mirror, trial.slot]
        judged.call(trial)
      end
      define_method(:verdict) do |mirror, tests, **|
        log << [:control, tests, mirror]
        control
      end
    end
  end

  def test_mirrored(isolated, control, **)
    Dir.mktmpdir do |root|
      File.write(File.join(root, "calc.rb"), "def a(x, y) = x > y\n")
      test_engine(yield, isolated: isolated, control: control)
        .new(registry: registry, root: root, tests: ["t1"], hard_timeout: 9, **)
        .rejudge(isolated.keys.map { |id| test_warm(id) }, label: "mutants (re-judged)")
    end
  end

  def test_rejudge(isolated:, control: Kimera::Execution::IsolatedOutcome.new(:survived), **)
    log = []
    [test_mirrored(isolated, control, **) { log }, log]
  end

  def test_quiet = { progress: test_bar([]) }

  def test_revisited(warm, isolated)
    registry.points.each { |point| point.revisit!(Kimera::Execution::BlockUse::REASON) }
    Dir.mktmpdir do |root|
      File.write(File.join(root, "calc.rb"), "def a(x, y) = x > y\n")
      test_engine([], isolated: isolated, control: Kimera::Execution::IsolatedOutcome.new(:survived))
        .new(registry: registry, root: root, tests: ["t1"], hard_timeout: 9, **test_quiet)
        .rejudge(warm, label: "mutants (re-judged)")
    end
  end

  def test_covered(id, status, tests)
    Kimera::MutantResult.new(mutant_id: id, status: status, file: "calc.rb", covering_tests: tests, detail: "warm")
  end

  # R6B3-M3: a mutant sent to a mirror only because the warm overlay cannot
  # settle it (a block it leaves unused, a lambda a macro keeps) was covered
  # and judged warm; the mirror runs every test near its file, not all of which
  # reach it, so the tests that covered it stay the warm ones.
  it "keeps the warm coverage of a mutant re-judged for a block it leaves unused" do
    first, second = ids
    warm = [test_covered(first, :survived, ["w"]), test_covered(second, :survived, ["w"])]
    results = test_revisited(warm, first => [:survived, nil], second => [:killed, nil])
    expect(results.map { |r| [r.status, r.covering_tests, r.note] })
      .to(eq([[:survived, ["w"], note.strip], [:killed, ["w", "k#{second}"], note.strip]]))
  end

  it "leaves a mutant no test reached warm uncovered unless its mirror kills it" do
    first, second = ids
    warm = [test_covered(first, :no_coverage, []), test_covered(second, :no_coverage, [])]
    results = test_revisited(warm, first => [:survived, nil], second => [:killed, nil])
    expect(results.map { |r| [r.status, r.covering_tests] }).to(eq([[:no_coverage, []], [:killed, ["k#{second}"]]]))
  end

  it "confirms a kill against the mutant's covering tests in another fresh mirror" do
    id = ids.first
    results, log = test_rejudge(isolated: { id => [:killed, nil] }, **test_quiet)
    expect(results.map(&:to_h)).to(
      match([include("status" => "killed", "covering_tests" => ["t#{id}"], "detail" => nil, "note" => "#{note}#{id}")])
    )
    (_, _, mutated), (_, tests, unmutated) = log
    expect([log.map(&:first), tests, unmutated == mutated]).to(eq([%i[mutant control], ["t#{id}"], false]))
  end

  it "confirms a timeout the same way" do
    results, log = test_rejudge(isolated: { ids.first => [:timeout, nil] }, **test_quiet)
    expect(results.map(&:status)).to(eq([:timeout]))
    expect(log.map(&:first)).to(eq(%i[mutant control]))
  end

  it "leaves a kill unjudged when the tests fail without the mutant too" do
    red = Kimera::Execution::IsolatedOutcome.new(:killed, ["t1"])
    results, = test_rejudge(isolated: { ids.first => [:killed, nil] }, control: red, **test_quiet)
    detail = "its tests fail in a fresh mirror without the mutant too (failing: t1)"
    expected = [[:harness_error, detail, nil, "#{note}#{ids.first}"]]
    expect(results.map { |r| [r.status, r.detail, r.failing_tests, r.note] }).to(eq(expected))
  end

  it "names the timeout of a control that ran past --hard-timeout" do
    slow = Kimera::Execution::IsolatedOutcome.new(:timeout).timed(9)
    results, = test_rejudge(isolated: { ids.first => [:killed, nil] }, control: slow, **test_quiet)
    expect(results.first.detail).to(
      eq(
        "its tests time out in a fresh mirror without the mutant too " \
          "(timed out after 9s without a test finishing); raise --hard-timeout"
      )
    )
  end

  it "reports a survivor or an isolated harness error as it is, without a control run" do
    first, second = ids
    isolated = { first => [:survived, nil], second => [:harness_error, "test child exited 1"] }
    results, log = test_rejudge(isolated: isolated, **test_quiet)
    expect(results.map { |r| [r.status, r.detail, r.note] })
      .to(eq([[:survived, nil, "#{note}#{first}"], [:harness_error, "test child exited 1", "#{note}#{second}"]]))
    expect(log.map(&:first)).to(eq(%i[mutant mutant]))
  end

  it "never counts the isolated tier's own failure as a kill" do
    results, log = test_rejudge(isolated: { ids.first => [:error, "Errno::ENOSPC: full"] }, **test_quiet)
    expected = [[:harness_error, "the isolated tier could not stage it: Errno::ENOSPC: full"]]
    expect(results.map { |r| [r.status, r.detail] }).to(eq(expected))
    expect(log.map(&:first)).to(eq([:mutant]))
  end

  # A slot names the test database a mirror takes; one mirror at a time keeps
  # the project's own database.
  it "gives each concurrent mirror a slot, and a lone mirror none", :aggregate_failures do
    isolated = ids.to_h { |id| [id, [:survived, nil]] }
    _results, alone = test_rejudge(isolated: isolated, jobs: 1, **test_quiet)
    expect(alone.map(&:last).uniq).to(eq([nil]))
    _results, together = test_rejudge(isolated: isolated, jobs: 2, **test_quiet)
    expect(together.map(&:last)).to(all(be_between(0, 1)))
  end

  it "judges each mutant in a mirror of its own, across jobs, in the warm order" do
    isolated = ids.to_h { |id| [id, [:survived, nil]] }
    results, log = test_rejudge(isolated: isolated, jobs: 2, **test_quiet)
    expect(results.map(&:mutant_id)).to(eq(ids))
    expect(log.map(&:last).uniq.size).to(eq(2))
  end

  it "notes the pass, then brackets it with progress, ticking each verdict" do
    events = []
    test_rejudge(isolated: { ids.first => [:survived, nil] }, progress: test_bar(events))
    expect(events).to(
      eq(
        [
          [:note, "re-judging 1 mutant(s) the warm pass could not judge, each in a fresh mirror"],
          [:start, 1, "mutants (re-judged)"], %i[tick survived], [:finish]
        ]
      )
    )
  end

  it "writes nothing to stderr itself" do
    expect { test_rejudge(isolated: { ids.first => [:survived, nil] }) }.not_to(output.to_stderr)
  end

  it "reads as plain lines on a stream that is not a terminal" do
    io = StringIO.new
    test_rejudge(isolated: { ids.first => [:survived, nil] }, progress: Kimera::Report::Progress.new(io: io))
    expect(io.string.lines.first(2)).to(
      eq(
        [
          "kimera: re-judging 1 mutant(s) the warm pass could not judge, each in a fresh mirror\n",
          "kimera: mutants (re-judged) 0/1 0%  0:00 elapsed\n"
        ]
      )
    )
  end
end
