# frozen_string_literal: true

require "json"
require "kimera/cli/run"
require "kimera/frameworks/rspec_suite"
require "kimera/registry/builder"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run::Pass) do
  let(:source) { "def m(a, b)\n  a > b\nend\n" }
  let(:registry) { Kimera::RegistryScan.new.source(source, file: "x.rb") }
  let(:id) { registry.index.keys.first }
  let(:built) { [] }

  around { |example| Dir.mktmpdir("kimera-pass") { |dir| Dir.chdir(dir) { example.run } } }

  before do
    File.write("x.rb", source)
    File.write("x_spec.rb", "")
    report = Kimera::RunReport.new(results: [])
    harness = instance_double(Kimera::Execution::Harness, timings: {}, flakes: nil, coverage: { id => ["t1"] })
    allow(harness).to(receive_messages(warm!: nil, run: report))
    allow(Kimera::Execution::Harness).to(receive(:build)) { |**options| (built << options) && harness }
  end

  def pass(**over)
    options = { framework: "rspec", source_root: ".", tests: ["*_spec.rb"], paths: ["x.rb"], coverage: true }
    adapter = instance_double(Kimera::Frameworks::RSpecSuite, catalog: {}, finish: nil, test_ids: %w[t1 t2])
    described_class.new(registry, options.merge(jobs: 1, **over), adapter).call([id])
  end

  it "stores the coverage map after a full run's baseline under --reuse-coverage" do
    pass(reuse_coverage: true)
    expect(JSON.parse(File.read("tmp/kimera/coverage.json")).values_at("coverage", "tests"))
      .to(eq([{ "x.rb" => ["t1"] }, %w[t1 t2]]))
  end

  it "hands the harness the tests a --reuse-coverage run's baseline measures" do
    pass(reuse_coverage: true, since: "HEAD")
    expect { built.first.fetch(:measured).call(%w[t1]) }
      .to(output(/not reusing the stored coverage map/).to_stderr_from_any_process)
  end
end
