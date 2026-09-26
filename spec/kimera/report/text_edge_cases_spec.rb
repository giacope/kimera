# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/report/text"
require "kimera/results/run_report"
require "stringio"

RSpec.describe(Kimera::Report::Text) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x <= y
      end
    RUBY
  end
  let(:mutant) { registry.each.find { |m, _| m.label == "<= => <" }.first }

  def render(results: [], leaks: [], scope: nil, color: false)
    io = StringIO.new
    described_class.new(registry, io: io, color: color).report(
      Kimera::RunReport.new(results: results, leaks: leaks),
      scope: scope
    )
    io.string
  end

  def survivor(covering: [])
    Kimera::MutantResult.new(
      mutant_id: mutant.id, status: :survived, file: "calc.rb",
      duration: 0.1, covering_tests: covering
    )
  end

  it "prints a scope line when given" do
    expect(render(scope: "Incremental: 1 mutant")).to(include("Incremental: 1 mutant"))
  end

  it "starts with the summary line when no scope is given" do
    # No stray blank line from puts(nil).
    expect(render).to(start_with("mutants="))
  end

  it "prints state-leak warnings", :aggregate_failures do
    leak = Kimera::LeakReport.new(mutant_id: 5, detail: "leaked badly")
    out = render(results: [survivor], leaks: [leak])
    expect(out).to(match(/\n\nState-leak warnings \(1\):/))
    expect(out).to(include("- leaked badly"))
  end

  it "omits the leak section when there are no leaks" do
    expect(render(results: [survivor])).not_to(include("State-leak warnings"))
  end

  def result(id)
    Kimera::MutantResult.new(mutant_id: id, status: :survived, file: "calc.rb", duration: 0.1)
  end

  it "lists survivors in ascending mutant-id order" do
    low, high = registry.each.map { |m, _| m.id }.minmax
    out = render(results: [high, low].map { |id| result(id) })
    expect(out.index("##{low}  ")).to(be < out.index("##{high}  "))
  end

  it "separates the survivors section and each entry with a blank line" do
    out = render(results: [survivor])
    expect(out).to(match(/\n\nSurviving mutants \(1\):\n\n  survived ##{mutant.id}/))
  end

  it "truncates the covering-test list and notes the remainder", :aggregate_failures do
    tests = (1..8).map { |i| "spec[#{i}]" }
    out = render(results: [survivor(covering: tests)])
    expect(out).to(include("covered by 8 test(s):"))
    expect(out).to(include("(+3 more)")) # 8 total, 5 shown
  end

  it "omits the truncation note when all covering tests are shown" do
    out = render(results: [survivor(covering: ["spec[1]"])])
    expect(out).not_to(include("more)")) # no "(+0 more)"
  end

  it "omits the covering line when no tests cover the survivor" do
    out = render(results: [survivor(covering: [])])
    expect(out).not_to(include("covered by"))
  end

  it "wraps header, verdict, and diff markers in SGR sequences when color is on", :aggregate_failures do
    out = render(results: [survivor(covering: ["spec[1]"])], color: true)
    # Any SGR code passes; the exact color is style, not contract.
    expect(out).to(match(/\e\[\d+mSurviving mutants \(1\):\e\[0m/))
    expect(out).to(match(/\e\[\d+msurvived\e\[0m/))
    expect(out).to(match(/\e\[\d+m-\e\[0m/))
    expect(out).to(match(/\e\[\d+m\+\e\[0m/))
  end

  # StringIO responds to tty? but returns false, so the guard must be AND, not OR.
  it "auto-detects: no color on a non-tty stream" do
    io = StringIO.new
    run = Kimera::RunReport.new(results: [survivor])
    described_class.new(registry, io: io, color: nil).report(run)
    expect(io.string).not_to(include("\e["))
  end

  it "auto-detects: color on a tty stream" do
    io = StringIO.new
    def io.tty? = true
    run = Kimera::RunReport.new(results: [survivor])
    old = ENV.delete("NO_COLOR")
    described_class.new(registry, io: io, color: nil).report(run)
    expect(io.string).to(include("\e["))
  ensure
    ENV["NO_COLOR"] = old if old
  end

  it "respects NO_COLOR when color is not explicitly requested" do
    io = StringIO.new
    def io.tty? = true
    run = Kimera::RunReport.new(results: [survivor])
    old = ENV.fetch("NO_COLOR", nil)
    ENV["NO_COLOR"] = "1"
    described_class.new(registry, io: io, color: nil).report(run)
    expect(io.string).not_to(include("\e["))
  ensure
    ENV["NO_COLOR"] = old
  end

  it "lets an explicit color choice override NO_COLOR" do
    old = ENV.fetch("NO_COLOR", nil)
    ENV["NO_COLOR"] = "1"
    expect(render(results: [survivor], color: true)).to(include("\e["))
  ensure
    ENV["NO_COLOR"] = old
  end

  it "skips a survivor whose mutant is not in the registry", :aggregate_failures do
    orphan = Kimera::MutantResult.new(mutant_id: 999_999, status: :survived, file: "x.rb", duration: 0.0)
    out = render(results: [orphan])
    expect(out).to(include("Surviving mutants (1):"))
    expect(out).not_to(include("survived #999999"))
  end

  def point
    Kimera::MutationPoint.new(
      point_id: 1, file: "x.rb", operator: "comparison", node_type: "call_node",
      location: Kimera::Location.new(
        start_offset: 0, span: 5, start_line: 1,
        start_column: 0, end_line: 1, end_column: 5
      ),
      original_source: "a > b",
      mutants: [Kimera::Mutant.new(id: 1, label: "bogus", directive: { "type" => "???" })]
    )
  end

  def unknown
    Kimera::MutantResult.new(mutant_id: 1, status: :survived, file: "x.rb", duration: 0.0)
  end

  def output
    io = StringIO.new
    described_class.new(Kimera::Registry.new(points: [point]), io: io, color: false)
      .report(Kimera::RunReport.new(results: [unknown]))
    io.string
  end

  it "prints only the original line when the variant cannot be rendered", :aggregate_failures do
    out = output
    expect(out).to(include("- a > b"))
    expect(out).not_to(include("+ "))
  end
end
