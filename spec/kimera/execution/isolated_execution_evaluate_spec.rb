# frozen_string_literal: true

require "kimera/execution/isolated"
require "kimera/registry/builder"
require "tmpdir"

# An error raised outside every test (a load error, a hook) is not taken for
# a kill on its first sighting: the mutant runs once more, and only an error
# that recurs kills it.
RSpec.describe(Kimera::Execution::IsolatedExecution, "#evaluate", :aggregate_failures) do
  let(:registry) do
    Kimera::RegistryScan.new.source("def a(x, y)\n  x > y\nend\n", file: "calc.rb")
  end

  let(:id) { registry.each.map { |mutant, _point| mutant.id }.first }
  let(:outside) { Kimera::Execution::IsolatedOutcome.new(:outside, [], "an error outside every test: boom") }

  def test_trial(mirror) = Kimera::Execution::Trial.new(id, mirror, Kimera::Overlay.new(registry), nil, 3)

  def test_settled(*outcomes)
    seen = []
    Dir.mktmpdir do |root|
      File.write(File.join(root, "calc.rb"), "def a(x, y)\n  x > y\nend\n")
      runner =
        Class.new(described_class) do
          define_method(:verdict) do |_mirror, _tests, slot: nil, **|
            seen << slot
            outcomes.shift
          end
        end.new(registry: registry, root: root, tests: ["t1"], coverage: { id => ["t1"] })
      Dir.mktmpdir do |mirror|
        FileUtils.cp(File.join(root, "calc.rb"), mirror)
        [runner.__send__(:evaluate, test_trial(mirror)), seen]
      end
    end
  end

  it "takes the second run's verdict when the first broke outside every test" do
    result, seen = test_settled(outside, Kimera::Execution::IsolatedOutcome.new(:survived))
    expect([result.status, seen]).to(eq([:survived, [3, 3]]))
    expect(test_settled(outside, Kimera::Execution::IsolatedOutcome.new(:killed, ["t1"])).first.failing_tests)
      .to(eq(["t1"]))
  end

  it "kills the mutant only when the error recurs, saying so" do
    result, seen = test_settled(outside, outside)
    expect([result.status, seen.size]).to(eq([:killed, 2]))
    expect(result.detail).to(eq("an error outside every test: boom (it recurred in a second run with the mutant on)"))
  end

  it "runs once when the first verdict is inside a test" do
    _result, seen = test_settled(Kimera::Execution::IsolatedOutcome.new(:killed, ["t1"]))
    expect(seen).to(eq([3]))
  end
end
