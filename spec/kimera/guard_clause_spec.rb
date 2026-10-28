# frozen_string_literal: true

require "kimera/registry/builder"
require "kimera/runtime"
require "kimera/synthesis/overlay"
require "kimera/synthesis/unwoven"

# R6B6-M2: a dropped rescue or ensure clause is guarded on the clause alone
# (`rescue *(active ? [] : [IndexError])`, an ensure body under `if !active`),
# and its bake blanks the clause's lines, so the method runs its own body on
# its own lines in both tiers: a test that reads a line sees the mutation and
# nothing else (the warm side ran the body on the clause's `end` line, the bake
# rewrote a modifier `if` as a block one).
RSpec.describe(Kimera::GuardClause) do
  def overlay(code)
    operators = Kimera::Operators.build(keys: %w[rescue_clause ensure_clause])
    Kimera::Overlay.new(Kimera::RegistryScan.new(operators: operators).source(code, file: "c.rb"))
  end

  def woven(code) = overlay(code).synthesize("c.rb", code).source

  def baked(code, id) = overlay(code).bake("c.rb", code, id)

  def guard(id) = "::Kimera::RUNTIME.active?(#{id})"

  let(:loader) { <<~RUBY }
    class ClauseLoader
      def read(lines)
        first = lines.fetch(0)
        raise ArgumentError, "blank first line" if first.empty?
        first
      rescue IndexError
        ""
      end
    end
  RUBY

  # Loads a program into a fresh ClauseLoader and reads the line the
  # ArgumentError was raised on, with `active` on.
  def raised(source, active = nil)
    stub_const("ClauseLoader", Class.new)
    Kimera::Overlay::Source.new(source).evaluate("c.rb")
    Kimera::RUNTIME.during(active) { ClauseLoader.new.read([""]) }
  rescue ArgumentError => error
    error.backtrace_locations.first.lineno
  end

  it "guards a rescue clause where it stands: its classes as a splat that rescues nothing while it is on" do
    expect(woven(loader)).to(eq(loader.sub("rescue IndexError", "rescue *(#{guard(1)} ? [] : [IndexError])")))
  end

  it "bakes the dropped clause as blank lines, every other line where it was" do
    expect(baked(loader, 1)).to(eq(loader.sub("  rescue IndexError\n    \"\"\n  end", "  ;\n\n  end")))
  end

  it "raises from the line the original raises on, warm with the mutant on and baked", :aggregate_failures do
    expect(raised(loader)).to(eq(4))
    expect(raised(woven(loader), 1)).to(eq(4))
    expect(raised(baked(loader, 1))).to(eq(4))
  end

  # The mutants a call to ClauseLoader#read reached; a raised ArgumentError is let through.
  def reached(lines)
    ledger = Kimera::RUNTIME.start!
    begin
      ClauseLoader.new.read(lines)
    rescue ArgumentError
      nil
    end
    Kimera::RUNTIME.stop!(ledger)
  end

  # Coverage: only a test that raises into the clause can kill its mutant.
  it "is reached where an exception reaches the clause, not by every call" do
    raised(woven(loader))
    expect([reached(["a"]), reached([""])]).to(eq([[], [1]]))
  end

  it "guards a bare rescue as one of StandardError, and a reference after its classes", :aggregate_failures do
    expect(woven("def m(v)\n  Integer(v)\nrescue\n  0\nend\n"))
      .to(eq("def m(v)\n  Integer(v)\nrescue *(#{guard(1)} ? [] : ::StandardError)\n  0\nend\n"))
    expect(woven("def m(v)\n  Integer(v)\nrescue => e\n  e\nend\n"))
      .to(eq("def m(v)\n  Integer(v)\nrescue *(#{guard(1)} ? [] : ::StandardError) => e\n  e\nend\n"))
    split = "def m(v)\n  Integer(v)\nrescue TypeError,\n       ArgumentError => e\n  e\nend\n"
    expect(woven(split))
      .to(eq(split.sub("TypeError,\n       ArgumentError", "*(#{guard(1)} ? [] : [TypeError,\n       ArgumentError])")))
  end

  it "guards an ensure body under the mutant's test, on the body's lines" do
    code = "def m(log)\n  log << 1\nensure\n  log << 2\n  log << 3\nend\n"
    expect(woven(code)).to(eq("def m(log)\n  log << 1\nensure; if !(#{guard(1)})\n  log << 2\n  log << 3; end\nend\n"))
  end

  def clauses = "def m(v)\n  x = begin\n    Integer(v)\n  rescue TypeError\n    1\n  rescue KeyError\n    2\n  end\nend"

  def looped = "def m(n)\n  begin\n    n -= 1\n  rescue ArgumentError\n    0\n  end while n > 0\nend\n"

  it "guards each clause of an explicit begin, a looped one too", :aggregate_failures do
    both = clauses.sub("rescue TypeError", "rescue *(#{guard(1)} ? [] : [TypeError])")
    expect(woven(clauses)).to(eq(both.sub("rescue KeyError", "rescue *(#{guard(2)} ? [] : [KeyError])")))
    expect(woven(looped)).to(eq(looped.sub("rescue ArgumentError", "rescue *(#{guard(1)} ? [] : [ArgumentError])")))
  end

  it "reads a guarded clause back as the clause with every mutant off" do
    code = "def m(v)\n  Integer(v)\nrescue TypeError, ArgumentError => e\n  e\nrescue\n  0\nensure\n  v.clear\nend\n"
    original = Kimera::Syntax.parse(code).value.statements.body.first
    expect(Kimera::Unwoven.new(Kimera::Syntax.parse(woven(code)).value).keeps?([original])).to(be(true))
  end

  it "reads a clause's own splats as written, not as a guard" do
    code = "def m(v)\n  Integer(v)\nrescue *(ERRORS)\n  0\nrescue *LIST\n  1\nend\n"
    tree = Kimera::Syntax.parse(code).value
    expect(Kimera::Outline.new(Kimera::Unguarded.new(tree).node).shape).to(eq(Kimera::Outline.new(tree).shape))
  end

  it "bakes a dropped last clause with its else folded in, and a begin left bare as its body", :aggregate_failures do
    code = "def m(v)\n  Integer(v)\nrescue ArgumentError\n  0\nelse\n  :ok\nend\n"
    expect(baked(code, 1)).to(eq("def m(v)\n  Integer(v)\n;\n\n;\n  :ok\nend\n"))
    code = "def m(v)\n  begin\n    Integer(v)\n  rescue ArgumentError\n    0\n  end\n  :ok\nend\n"
    expect(baked(code, 1)).to(eq("def m(v)\n  ;\n    Integer(v)\n  ;\n\n  ;\n  :ok\nend\n"))
  end

  it "bakes one dropped clause of several as blank lines, the others where they were", :aggregate_failures do
    code = "def m(v)\n  Integer(v)\nrescue TypeError\n  1\nrescue KeyError\n  2\nensure\n  v.clear\nend\n"
    expect(baked(code, 1)).to(eq(code.sub("rescue TypeError\n  1\n", ";\n\n")))
    expect(baked(code, 3)).to(eq(code.sub("ensure\n  v.clear\n", ";\n\n")))
  end

  it "bakes a dropped ensure as blank lines" do
    code = "def m(log)\n  log << 1\nensure\n  log << 2\nend\n"
    expect(baked(code, 1)).to(eq("def m(log)\n  log << 1\n;\n\nend\n"))
  end

  it "leaves a rescue modifier and an empty ensure to the guards around them", :aggregate_failures do
    modifier = Kimera::Syntax.parse("x rescue y").value.statements.body.first
    mutant = Kimera::Mutant.new(id: 1, label: "drop `rescue` modifier", directive: { "type" => "drop_rescue" })
    expect(described_class.new(modifier, mutant).edits).to(be_nil)
    expect(woven("def m\n  work\nensure\nend\n")).to(include("(!(#{guard(1)}) ? (begin; work"))
  end
end
