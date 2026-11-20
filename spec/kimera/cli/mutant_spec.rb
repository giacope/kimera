# frozen_string_literal: true

require "json"
require "kimera/cli/mutant"
require "stringio"
require "tmpdir"

using ResultFields
using PointFields

RSpec.describe(Kimera::CLI::Mutant, :aggregate_failures) do
  let(:sample) { File.expand_path("../../../examples/sample_app", __dir__) }
  let(:provenance) do
    { "framework" => "rspec", "source_root" => ".", "tests" => ["spec/**/*_spec.rb"] }
      .merge("operators" => Kimera::Operators.build.map(&:key), "coverage" => true, "isolated" => false)
  end

  def reported(registry, mutant, point)
    row = Kimera::MutantResult.new(mutant_id: mutant.to_i, status: :no_coverage, file: point.file)
    Kimera::RunReport.new(results: [row], registry: registry).annotate(run: provenance).to_h
  end

  def rerun(id, document)
    run = FakeRun.new
    Dir.mktmpdir do |dir|
      path = File.join(dir, "report.json").tap { |file| File.write(file, JSON.generate(document)) }
      described_class.new(io: StringIO.new, run: run).run([id.to_s, "--report", path, "--rerun"])
    end
    run.runs.fetch(0)
  end

  def focused(options)
    stub_const("ENV", ENV.to_h)
    registry = Kimera::CLI::Run::Sources.new.load(options)
    harness = FakeHarness.new
    Kimera::CLI::Run::Cycle.new(options, registry, digest: FakeDigest.new, alerts: FakeAlerts.new)
      .call(Kimera::CLI::Run::NullSelection.new, FakeBench.new(harness: harness))
    harness.asked.first.last => [id]
    [registry, *registry[id]]
  end

  def later
    full = Kimera::RegistryScan.new.build(Dir["app/**/*.rb"])
    mutant, point = full.each.find { |found, spot| spot.file.end_with?("pricing.rb") && found.to_s == "> => >=" }
    [full, mutant, point, rerun(mutant.to_i, reported(full, mutant, point))]
  end

  describe "a multi-file report" do
    def refocused
      full, mutant, point, argv = later
      alone, again, spot = focused(Kimera::CLI::Run::Arguments.new.parse(argv))
      found = [again.to_s, spot.location.range.begin, Kimera::MutantKeys.of(alone)[again.to_i], mutant.to_i, again.to_i]
      [argv.first(3), found, Kimera::MutantKeys.of(full)[mutant.to_i], mutant, point]
    end

    it "reruns a mutant from a later file", :aggregate_failures do
      Dir.chdir(sample) do
        head, found, key, mutant, point = refocused
        expect(head).to(eq(["app/services/pricing.rb", "--focus", key]))
        expect(found).to(eq([mutant.to_s, point.location.range.begin, key, 25, 3]))
      end
    end
  end
end
