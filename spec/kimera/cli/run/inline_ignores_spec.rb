# frozen_string_literal: true

require "kimera/cli/run"
require "kimera/registry/builder"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run::InlineIgnores) do
  around do |example|
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  end

  def rules(source)
    File.write("calc.rb", source)
    registry = Kimera::RegistryScan.new.build(["calc.rb"])
    described_class.new(registry, root: ".").rules
  end

  it "turns a trailing comment into a rule for the mutants starting on its line" do
    found = rules("def m(x)\n  x > 1 # kimera:disable: boundary is unobservable here\nend\n")
    expect(found).to(eq([{ file: "calc.rb", starts: 2, reason: "boundary is unobservable here" }]))
  end

  it "aims a disable-next-line comment at the following line, narrowed to the operators it names" do
    found = rules("def m(x)\n  # kimera:disable-next-line comparison, conditional : clamped upstream\n  x > 1\nend\n")
    rule = { file: "calc.rb", starts: 3, reason: "clamped upstream", operator: %w[comparison conditional] }
    expect(found).to(eq([rule]))
  end

  it "ignores comments that only mention the marker, and strings that carry it" do
    source = "def m(x)\n  # see kimera:disable docs\n  \"# kimera:disable: no\" if x > 1\n  # kimera:disabled\nend\n"
    expect(rules(source)).to(be_empty)
  end

  it "rejects a comment without a reason, naming where it is", :aggregate_failures do
    message = "calc.rb:2: kimera:disable needs a reason (# kimera:disable[-next-line] [OPERATOR ...]: REASON)"
    bare = "def m(x)\n  x > 1 # kimera:disable comparison\nend\n"
    blank = "def m(x)\n  x > 1 # kimera:disable comparison:   \nend\n"
    expect { rules(bare) }.to(raise_error(Kimera::UsageError, message))
    expect { rules(blank) }.to(raise_error(Kimera::UsageError, message))
  end

  it "rejects an operator it does not know" do
    expect { rules("def m(x)\n  x > 1 # kimera:disable comparsion: typo\nend\n") }.to(
      raise_error(Kimera::UsageError, /unknown operator\(s\): comparsion/)
    )
  end

  it "skips a scanned file that is no longer on disk" do
    File.write("calc.rb", "def m(x)\n  x > 1 # kimera:disable: gone\nend\n")
    registry = Kimera::RegistryScan.new.build(["calc.rb"])
    File.delete("calc.rb")
    expect(described_class.new(registry, root: ".").rules).to(be_empty)
  end

  describe "kimera run" do
    def run(source)
      File.write("calc.rb", source)
      allow(Kimera::Execution::Harness).to(receive(:build).and_wrap_original) do |original, **kwargs|
        original.call(**kwargs).tap do |harness|
          allow(harness).to(receive(:warm!))
          allow(harness).to(receive(:run).and_return(Kimera::RunReport.new(results: [])))
        end
      end
      out = StringIO.new
      errors = StringIO.new
      Kimera::CLI::Run.new(io: out, errors: errors).run(%w[calc.rb --no-report --max-ignored 0])
      [out.string, errors.string]
    end

    it "ignores the mutants a comment disables, budgeting them like any ignore entry", :aggregate_failures do
      out, errors = run("def m(x)\n  x > 1 # kimera:disable: boundary is unobservable\nend\n")
      expect(out).to(include("Ignoring 2 mutant(s) marked equivalent.", "ignored=2"))
      expect(errors).to(include("gate failed: ignored=2 > max_ignored=0"))
    end

    it "warns about a comment that disables nothing" do
      _, errors = run("def m(x)\n  # kimera:disable-next-line: nothing here\n\n  x > 1\nend\n")
      warning = "kimera: warning: kimera:disable comment matches no mutant (stale anchor?): calc.rb:3\n"
      expect(errors).to(include(warning))
    end
  end
end
