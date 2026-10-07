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
    allow(Kimera::FileSet).to(receive(:expand).and_call_original)
    expect(narrowing(["spec/**/*_spec.rb"]).note).to(be_nil)
    expect(Kimera::FileSet).not_to(have_received(:expand))
  end

  it "groups thousands in the counts" do
    counts = [3, 1_120, 1_234_567].map { |number| narrowing([]).__send__(:count, number) }
    expect(counts).to(eq(%w[3 1,120 1,234,567]))
  end

  describe "kimera run" do
    before { File.write("calc.rb", "def m(a, b)\n  a > b\nend\n") }

    def run(*argv)
      allow(Kimera::Execution::Harness).to(receive(:build).and_wrap_original) do |original, **kwargs|
        original.call(**kwargs).tap do |harness|
          allow(harness).to(receive(:warm!))
          allow(harness).to(receive(:run).and_return(Kimera::RunReport.new(results: [])))
        end
      end
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
  end
end
