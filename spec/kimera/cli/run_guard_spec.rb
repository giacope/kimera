# frozen_string_literal: true

require "fileutils"
require "kimera/cli"
require "kimera/cli/run"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run, :aggregate_failures) do
  def guarded(root, results = [])
    errors = StringIO.new
    harness = FakeHarness.new { yield.then { Kimera::RunReport.new(results: results) } }
    run = described_class.new(io: StringIO.new, errors: errors, bench: FakeBench.new(harness: harness))
    outcome = run.run([File.join(root, "calc.rb"), "--source-root", root, "--report", File.join(root, "report.json")])
    [ended(outcome, StringIO.new, errors), errors.string]
  end

  def project(root)
    FileUtils.mkdir_p(File.join(root, "spec"))
    { "calc.rb" => "def m(a, b)\n  a > b\nend\n", "spec/calc_spec.rb" => "", "fixture.rb" => "1\n" }
      .each { |path, body| File.write(File.join(root, path), body) }
    root
  end

  def deleting(root)
    guarded(project(root)) { File.delete(File.join(root, "fixture.rb")) }
  end

  it "fails a run that changed the project's files, naming them", :aggregate_failures do
    Dir.mktmpdir do |root|
      code, said = deleting(root)
      expect(code).to(eq(1))
      expect(said).to(start_with("kimera: the run changed 1 tracked file(s)").and(include("\n  fixture.rb\n")))
    end
  end

  it "keeps the run's own exit code when the project is as it was" do
    Dir.mktmpdir do |root|
      survivor = Kimera::MutantResult.new(mutant_id: 1, status: :survived, file: "calc.rb")
      expect(guarded(project(root)) { 0 }).to(eq([0, ""]))
      expect(guarded(root, [survivor]) { 0 }).to(eq([2, "kimera: gate failed: survivors=1 > max_survivors=0\n"]))
    end
  end
end
