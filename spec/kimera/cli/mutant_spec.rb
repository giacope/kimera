# frozen_string_literal: true

require "json"
require "kimera/cli/mutant"
require "stringio"
require "tmpdir"

using ResultFields

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

  # The arguments of the run a --rerun of mutant +id+ in +document+ asks for.
  def rerun(id, document)
    run = FakeRun.new
    Dir.mktmpdir do |dir|
      path = File.join(dir, "report.json").tap { |file| File.write(file, JSON.generate(document)) }
      described_class.new(io: StringIO.new, run: run).run([id.to_s, "--report", path, "--rerun"])
    end
    run.runs.fetch(0)
  end

  def focused(options)
    registry = Kimera::CLI::Run::Sources.new.load(options)
    Kimera::CLI::Run::Cycle.new(options, registry, digest: nil).__send__(:focus, registry.index.keys) => [id]
    [registry, *registry[id]]
  end

  # A rerun scans only the mutant's file, where ordinals restart at 1, so
  # focusing the report's ordinal missed a second file's mutant ("not in
  # scope") or picked a different one. It focuses the key instead.
  # In the sample's full scan: the scan, a mutant of a later file, its point,
  # and the arguments of its rerun.
  def later_rerun
    full = Kimera::RegistryScan.new.build(Dir["app/**/*.rb"])
    mutant, point = full.each.find { |found, spot| spot.file.end_with?("pricing.rb") && found.to_s == "> => >=" }
    [full, mutant, point, rerun(mutant.to_i, reported(full, mutant, point))]
  end

  describe "a multi-file report" do
    around { |example| Dir.chdir(sample) { example.run } }

    it "reruns a mutant from a later file", :aggregate_failures do
      full, mutant, point, argv = later_rerun
      alone, again, spot = focused(Kimera::CLI::Run::Arguments.new.parse(argv))
      key = Kimera::MutantKeys.of(full)[mutant.to_i]
      expect(argv.first(3)).to(eq(["app/services/pricing.rb", "--focus", key]))
      expect([again.to_s, spot.location.range.begin, Kimera::MutantKeys.of(alone)[again.to_i], mutant.to_i, again.to_i])
        .to(eq([mutant.to_s, point.location.range.begin, key, 25, 3]))
    end
  end
end
