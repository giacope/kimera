# frozen_string_literal: true

require "kimera/execution/isolated"
require "kimera/registry/builder"
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
      def enabled? = true
      define_method(:start) { |total, label| @s << [:start, total, label] }
      define_method(:tick) { |status| @s << [:tick, status] }
      define_method(:finish) { @s << [:finish] }
    end.new(sink)
  end

  def test_warm(id)
    Kimera::MutantResult.new(mutant_id: id, status: :harness_error, file: "calc.rb", detail: "warm #{id}")
  end

  # isolated: id => [status, detail]; control: the unmutated outcome.
  def test_engine(log, isolated:, control:)
    Class.new(described_class) do
      define_method(:evaluate) do |trial|
        log << [:mutant, trial.id, trial.mirror]
        status, detail = isolated.fetch(trial.id)
        Kimera::MutantResult.new(
          mutant_id: trial.id, status: status, file: "calc.rb", covering_tests: ["t#{trial.id}"], detail: detail
        )
      end
      define_method(:verdict) do |mirror, tests|
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

  it "confirms a kill against the mutant's covering tests in another fresh mirror" do
    id = ids.first
    results, log = test_rejudge(isolated: { id => [:killed, nil] }, **test_quiet)
    expected = { "status" => "killed", "covering_tests" => ["t#{id}"], "detail" => nil, "note" => "#{note}#{id}" }
    expect(results.map(&:to_h)).to(match([include(expected)]))
    (_, _, mutated), (_, tests, unmutated) = log
    expect(log.map(&:first)).to(eq(%i[mutant control]))
    expect(tests).to(eq(["t#{id}"]))
    expect(unmutated).not_to(eq(mutated))
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
    slow = Kimera::Execution::IsolatedOutcome.new(:timeout)
    results, = test_rejudge(isolated: { ids.first => [:killed, nil] }, control: slow, **test_quiet)
    expect(results.first.detail).to(eq("its tests fail in a fresh mirror without the mutant too (timed out after 9s)"))
  end

  it "reports a survivor or an isolated harness error as it is, without a control run" do
    first, second = ids
    isolated = { first => [:survived, nil], second => [:harness_error, "test child exited 1"] }
    results, log = test_rejudge(isolated: isolated, **test_quiet)
    expected = [[:survived, nil, "#{note}#{first}"], [:harness_error, "test child exited 1", "#{note}#{second}"]]
    expect(results.map { |r| [r.status, r.detail, r.note] }).to(eq(expected))
    expect(log.map(&:first)).to(eq(%i[mutant mutant]))
  end

  it "never counts the isolated tier's own failure as a kill" do
    results, log = test_rejudge(isolated: { ids.first => [:error, "Errno::ENOSPC: full"] }, **test_quiet)
    expected = [[:harness_error, "the isolated tier could not stage it: Errno::ENOSPC: full"]]
    expect(results.map { |r| [r.status, r.detail] }).to(eq(expected))
    expect(log.map(&:first)).to(eq([:mutant]))
  end

  it "judges each mutant in a mirror of its own, across jobs, in the warm order" do
    isolated = ids.to_h { |id| [id, [:survived, nil]] }
    results, log = test_rejudge(isolated: isolated, jobs: 2, **test_quiet)
    expect(results.map(&:mutant_id)).to(eq(ids))
    expect(log.map(&:last).uniq.size).to(eq(2))
  end

  it "brackets the pass with the progress bar, ticking each verdict" do
    events = []
    test_rejudge(isolated: { ids.first => [:survived, nil] }, progress: test_bar(events))
    expect(events).to(eq([[:start, 1, "mutants (re-judged)"], %i[tick survived], [:finish]]))
  end

  it "stays quiet on stderr while the bar renders" do
    expect { test_rejudge(isolated: { ids.first => [:survived, nil] }, **test_quiet) }.not_to(output.to_stderr)
  end

  it "says what it re-judges on stderr when the bar is off" do
    announced = /\Akimera: re-judging 1 mutant\(s\) the warm pass could not judge, each in a fresh mirror\n/
    expect { test_rejudge(isolated: { ids.first => [:survived, nil] }) }.to(output(announced).to_stderr)
  end
end
