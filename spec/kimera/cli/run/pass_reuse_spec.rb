# frozen_string_literal: true

require "json"
require "kimera/cli/run"
require "kimera/registry/builder"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run::Pass) do
  let(:source) { "def m(a, b)\n  a > b\nend\n" }
  let(:registry) { Kimera::RegistryScan.new.source(source, file: "x.rb") }
  let(:id) { registry.index.keys.first }
  let(:harness) { FakeHarness.new(coverage: { id => ["t1"] }) }

  def inside
    Dir.mktmpdir("kimera-pass") do |dir|
      Dir.chdir(dir) do
        File.write("x.rb", source)
        File.write("x_spec.rb", "")
        yield
      end
    end
  end

  def pass(**over)
    options = { framework: "rspec", source_root: ".", tests: ["*_spec.rb"], paths: ["x.rb"], coverage: true }
      .merge(configured_paths: ["x.rb"])
    bench = FakeBench.new(harness: harness)
    described_class.new(registry, options.merge(jobs: 1, **over), FakeSuite.new(%w[t1 t2]), bench).call([id])
  end

  it "stores the coverage map after a full run's baseline under --reuse-coverage" do
    inside do
      pass(reuse_coverage: true)
      expect(JSON.parse(File.read("tmp/kimera/coverage.json")).values_at("coverage", "tests"))
        .to(eq([{ "x.rb" => ["t1"] }, %w[t1 t2]]))
    end
  end

  it "hands the harness the tests a --reuse-coverage run's baseline measures" do
    inside do
      pass(reuse_coverage: true)
      pass(reuse_coverage: true, since: "HEAD")
      expect { harness.settings.fetch(:measured).call(%w[t1]) }
        .to(output(/reusing the coverage map from .*: the baseline runs 1 of 1 tests/).to_stderr_from_any_process)
    end
  end
end
