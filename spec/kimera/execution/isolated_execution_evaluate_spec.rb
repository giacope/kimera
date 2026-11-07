# frozen_string_literal: true

require "kimera/execution/isolated"
require "kimera/registry/builder"
require "tmpdir"

RSpec.describe(Kimera::Execution::IsolatedExecution, "#evaluate", :aggregate_failures) do
  let(:registry) do
    Kimera::RegistryScan.new.source("def a(x, y)\n  x > y\nend\n", file: "calc.rb")
  end

  let(:id) { registry.each.map { |mutant, _point| mutant.id }.first }
  let(:outside) { Kimera::Execution::IsolatedOutcome.new(:outside, [], "an error outside every test: boom") }

  def test_bay(mirror) = Kimera::Execution::Bay.new(mirror, 3, Kimera::Overlay.new(registry))

  def test_runner(root, outcomes, seen)
    seated = method(:seat)
    Class.new(described_class) do
      define_method(:verdict) do |bay, _tests, first: false|
        mirror, slot = seated.call(bay)
        seen << [slot, File.basename(mirror).start_with?("kimera-isolated"), first]
        outcomes.shift
      end
    end.new(registry: registry, root: root, tests: ["t1"], coverage: { id => ["t1"] })
  end

  def test_settled(*outcomes)
    seen = []
    Dir.mktmpdir do |root|
      File.write(File.join(root, "calc.rb"), "def a(x, y)\n  x > y\nend\n")
      runner = test_runner(root, outcomes, seen)
      Dir.mktmpdir do |mirror|
        FileUtils.cp(File.join(root, "calc.rb"), mirror)
        [runner.__send__(:evaluate, id, test_bay(mirror)), seen]
      end
    end
  end

  it "takes the second run's verdict when the first broke outside every test" do
    result, seen = test_settled(outside, Kimera::Execution::IsolatedOutcome.new(:survived))
    expect([result.status, seen]).to(eq([:survived, [[3, false, true], [3, false, true]]]))
    expect(test_settled(outside, Kimera::Execution::IsolatedOutcome.new(:killed, ["t1"])).first.failing_tests)
      .to(eq(["t1"]))
  end

  it "kills the mutant when the error recurs and a fresh mirror without the mutant runs clean", :aggregate_failures do
    result, seen = test_settled(outside, outside, Kimera::Execution::IsolatedOutcome.new(:survived))
    expect([result.status, seen]).to(eq([:killed, [[3, false, true], [3, false, true], [3, true, false]]]))
    expect(result.detail).to(
      eq("an error outside every test: boom (it recurred with the mutant on; a fresh mirror without it runs clean)")
    )
  end

  it "leaves it unjudged when the error occurs without the mutant too", :aggregate_failures do
    result, seen = test_settled(outside, outside, outside)
    expect([result.status, seen.size]).to(eq([:harness_error, 3]))
    expect(result.detail).to(
      eq(
        "an error outside every test: boom; without the mutant too (an error outside every test: boom), " \
          "so it is no kill"
      )
    )
  end

  it "runs once when the first verdict is inside a test" do
    _result, seen = test_settled(Kimera::Execution::IsolatedOutcome.new(:killed, ["t1"]))
    expect(seen).to(eq([[3, false, true]]))
  end
end
