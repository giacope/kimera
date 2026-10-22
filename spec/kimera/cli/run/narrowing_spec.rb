# frozen_string_literal: true

require "json"
require "kimera/cli/run"
require "stringio"
require "tmpdir"

# --tests replaces the configured glob. A run narrowed that way says so, since
# its survivors may be killed by the tests it left out.
RSpec.describe(Kimera::CLI::Run::Narrowing) do
  around do |example|
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  end

  before do
    FileUtils.mkdir_p("spec/slow")
    %w[spec/a_spec.rb spec/b_spec.rb spec/slow/c_spec.rb].each { |file| File.write(file, "") }
  end

  def narrowing(tests, configured = ["spec/**/*_spec.rb"], exclude: [])
    described_class.new(tests: tests, configured_tests: configured, exclude_tests: exclude)
  end

  let(:note) do
    "narrowed run: --tests matched 1 of 3 test files from the configured tests: glob; " \
      "survivors may be killed by tests outside it"
  end

  it "counts the configured test files the run kept", :aggregate_failures do
    narrowed = narrowing(["spec/a_spec.rb"])
    expect(narrowed.note).to(eq(note))
    expect(narrowed.provenance).to(eq("narrowed" => true, "configured_tests" => ["spec/**/*_spec.rb"]))
  end

  it "leaves excluded test files out of both counts" do
    expect(narrowing(["spec/a_spec.rb"], exclude: ["spec/slow/**"]).note).to(include("matched 1 of 2 test files"))
  end

  it "matches a file however its glob spells the path" do
    expect(narrowing([File.expand_path("spec/*_spec.rb")]).note).to(include("matched 2 of 3"))
  end

  it "is silent when --tests keeps every configured test file", :aggregate_failures do
    wider = narrowing(["spec/**/*_spec.rb", "test/**/*_test.rb"])
    expect(wider.note).to(be_nil)
    expect(wider.provenance).to(eq("narrowed" => false))
  end

  it "doesn't expand the globs when --tests is the configured glob", :aggregate_failures do
    allow(Kimera::FileSet).to(receive(:new).and_call_original)
    expect(narrowing(["spec/**/*_spec.rb"]).note).to(be_nil)
    expect(Kimera::FileSet).not_to(have_received(:new))
  end

  it "groups thousands in the counts" do
    counts = [3, 1_120, 1_234_567].map { |number| narrowing([]).__send__(:count, number) }
    expect(counts).to(eq(%w[3 1,120 1,234,567]))
  end

  describe "kimera run" do
    before { File.write("calc.rb", "def m(a, b)\n  a > b\nend\n") }

    def run(*argv)
      stub_harness
      out = StringIO.new
      Kimera::CLI::Run.new(io: out, errors: StringIO.new).run(["calc.rb", "--report", "report.json", *argv])
      [out.string.lines(chomp: true), JSON.parse(File.read("report.json"))["run"]]
    end

    it "prints the note above the summary and records the narrowing", :aggregate_failures do
      lines, provenance = run("--tests", "spec/a_spec.rb")
      summary = "mutants=0 killed=0 survived=0 timeout=0 error=0 no_coverage=0 score=n/a (nothing to mutate)"
      expect(lines.first(2)).to(eq([note, summary]))
      expect(provenance).to(include("narrowed" => true, "configured_tests" => ["spec/**/*_spec.rb"]))
    end

    it "prints nothing extra for the configured glob", :aggregate_failures do
      lines, provenance = run
      expect(lines.first).to(start_with("mutants=0"))
      expect(provenance).to(include("narrowed" => false))
    end

    def adapter_for(*argv)
      built = stub_harness
      Kimera::CLI::Run.new(io: StringIO.new, errors: StringIO.new).run(["calc.rb", "--report", "report.json", *argv])
      [built.first[:adapter], JSON.parse(File.read("report.json"))["run"]]
    end

    # rack's one root-only test, without the other 26 in its file.
    it "leaves out the tests --exclude-test-name names, and records the pattern", :aggregate_failures do
      adapter, provenance = adapter_for("--exclude-test-name", "unreadable", "--exclude-test-name", "root only")
      expect(adapter).to(be_a(Kimera::Frameworks::NameExclusion))
      expect(adapter.instance_variable_get(:@patterns)).to(eq(["unreadable", "root only"]))
      expect(provenance).to(include("exclude_test_names" => ["unreadable", "root only"]))
      plain, = adapter_for
      expect(plain).not_to(be_a(Kimera::Frameworks::NameExclusion))
      expect(plain).to(be_a(Kimera::Frameworks::Suite))
    end

    def uncovered(*argv)
      stub_harness([Kimera::MutantResult.new(mutant_id: 1, status: :no_coverage, file: "calc.rb")])
      out = StringIO.new
      Kimera::CLI::Run.new(io: out, errors: StringIO.new).run(["calc.rb", "--report", "report.json", *argv])
      out.string
    end

    it "heads a narrowed run's uncovered mutants as not covered by the narrowed tests", :aggregate_failures do
      expect(uncovered("--tests", "spec/a_spec.rb", "--no-count-no-coverage")).to(
        include("1 mutant(s) not covered by the narrowed tests; list them with")
      )
      expect(uncovered("--no-count-no-coverage")).to(include("1 mutant(s) have no covering test; list them with"))
      expect(uncovered("--tests", "spec/a_spec.rb", "--fail-on-no-coverage")).to(
        include("Mutants not covered by the narrowed tests (1):")
      )
      expect(uncovered("--fail-on-no-coverage")).to(include("Mutants with no covering test (1):"))
    end
  end
end
