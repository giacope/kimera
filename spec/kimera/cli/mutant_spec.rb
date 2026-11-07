# frozen_string_literal: true

require "json"
require "kimera/cli/mutant"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Mutant, :aggregate_failures) do
  let(:sample) { File.expand_path("../../../examples/sample_app", __dir__) }
  let(:provenance) do
    { "framework" => "rspec", "source_root" => ".", "tests" => ["spec/**/*_spec.rb"] }
      .merge("operators" => Kimera::Operators.build.map(&:key), "coverage" => true, "isolated" => false)
  end

  def reported(registry, mutant, point)
    row = Kimera::MutantResult.new(mutant_id: mutant.id, status: :no_coverage, file: point.file)
    Kimera::RunReport.new(results: [row], registry: registry).document(provenance)
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
    registry = Kimera::CLI::Run::Sources.new.load(options)
    Kimera::CLI::Run::Cycle.new(options, registry, digest: nil).__send__(:focus, registry.index.keys) => [id]
    [registry, *registry.point(id)]
  end

  def later_rerun
    full = Kimera::RegistryScan.new.build(Dir["app/**/*.rb"])
    mutant, point = full.each.find { |found, spot| spot.file.end_with?("pricing.rb") && found.label == "> => >=" }
    [full, mutant, point, rerun(mutant.id, reported(full, mutant, point))]
  end

  describe "a multi-file report" do
    around { |example| Dir.chdir(sample) { example.run } }

    it "reruns a mutant from a later file", :aggregate_failures do
      full, mutant, point, argv = later_rerun
      alone, again, spot = focused(Kimera::CLI::Run::Arguments.new.parse(argv))
      expect(argv.first(3)).to(eq(["app/services/pricing.rb", "--focus", full.keys[mutant.id]]))
      expect([again.label, spot.location.start_line, alone.keys[again.id], mutant.id, again.id])
        .to(eq([mutant.label, point.location.start_line, full.keys[mutant.id], 25, 3]))
    end
  end
end
