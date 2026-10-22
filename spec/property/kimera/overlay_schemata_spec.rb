# frozen_string_literal: true

require_relative "../property_helper"

# Kimera compiles every mutant of a file into one guarded program and flips
# them at runtime. These properties pin that the flip is faithful: with
# mutant k active the program *is* mutant k, and with none active it *is*
# the original. See support/schemata_projection.rb for the reduction.
RSpec.describe(Kimera::Overlay) do
  let(:programs) { RubyPrograms.new(depth: 2) }

  def render(program) = RubyPrograms.render(program)

  def explain(mismatches)
    id, got, want = mismatches.first
    "mutant #{id} reduces to\n#{got.inspect}\nbut its bake is\n#{want.inspect}"
  end

  def every_id(registry) = registry.each.map { |mutant, _| mutant.id }

  # Every mutant is applied once and guarded, or skipped: none twice, none lost.
  def accounted(schemata)
    applied = schemata.result.mutant_ids.sort
    reported = (applied + schemata.result.skipped_unsafe).sort
    expect(applied: applied, guarded: schemata.guards.uniq.sort, reported: reported)
      .to(eq(accounting(applied, schemata.registry)))
  end

  def accounting(applied, registry)
    { applied: applied.uniq, guarded: applied.uniq, reported: every_id(registry).sort }
  end

  # One synthesis per program serves every check; synthesis is the costly part.
  it "is each mutant when it is active and the original when none is, and guards every mutant it reports" do
    for_all(programs, runs: 100) do |program|
      schemata = SchemataProjection.check(render(program))
      mismatches = schemata.mismatches
      said = -> { mismatches.empty? ? "with no mutant active, the program changed" : explain(mismatches) }
      expect([mismatches, schemata.projected(nil)]).to(eq([[], schemata.original]), said)
      accounted(schemata)
    end
  end

  # End to end through Ruby itself: load the schemata once, flip each mutant,
  # and compare every call with the same call on its baked source. Calls pass
  # zero to three positionals and may omit `c:`, so defaults are evaluated,
  # skipped, and rebound.
  describe "running a flipped mutant" do
    let(:inputs) do
      values = [-3, -1, 0, 1, 2, 5, nil, "4"]
      Pbt.array(Pbt.tuple(Pbt.array(Pbt.one_of(*values), max: 3), Pbt.one_of(:omitted, *values)), min: 1, max: 5)
    end

    # A removed default raises from inside the method ("missing argument: b",
    # "missing keyword: c") where the real signature fails its arity check
    # ("wrong number of arguments", "missing keyword: :c"). That wording is
    # the one difference this comparison excuses; see SchemataProjection.
    def outcome(receiver, (positional, keyword))
      [:returned, plain(receiver.m(*positional, **(keyword == :omitted ? {} : { c: keyword })))]
    rescue StandardError => error
      [:raised, error.class, SchemataProjection.worded(error)]
    end

    # A returned nil mutant returns a fresh `Object.new`, equal to no other.
    def plain(value) = value.instance_of?(Object) ? Object : value

    # Generated code may test a literal (`if "s"`); Ruby's parse warning is noise.
    def loaded(source)
      Object.new.extend(Module.new.tap { |mod| Kimera::Warnings::SILENCED.during { mod.module_eval(source) } })
    end

    # One live object serves every mutant; each bake is fresh, so the live
    # one forgets the ivars (`@v`) an earlier mutant's calls set.
    def flipped(live, id, calls)
      live.instance_variables.each { |name| live.remove_instance_variable(name) }
      Kimera::RUNTIME.active = id
      calls.map { |call| outcome(live, call) }
    ensure
      Kimera::RUNTIME.active = nil
    end

    it "behaves exactly like its bake on every input" do
      for_all(programs, inputs, runs: 40) do |program, calls|
        schemata = SchemataProjection.check(render(program))
        live = loaded(schemata.result.source)
        schemata.result.mutant_ids.each do |id|
          bake = loaded(schemata.overlay.bake("x.rb", schemata.source, id))
          expect(flipped(live, id, calls)).to(eq(calls.map { |call| outcome(bake, call) }), "mutant #{id}")
        end
      end
    end
  end

  # The same reduction over real code: the fixtures, and a seeded sample of
  # kimera's own sources (PBT_SCALE widens the sample; all of lib/ takes
  # about 5 minutes).
  it "reduces to each bake across real files" do
    root = File.expand_path("../../..", __dir__)
    sample(Dir[File.join(root, "{lib,examples}/**/*.rb")], (6 * PropertyRuns::SCALE).ceil).each do |path|
      schemata = SchemataProjection.check(File.read(path, encoding: Encoding::UTF_8))
      mismatches = schemata.mismatches
      expect(mismatches).to(be_empty, -> { "#{path}: #{explain(mismatches)}" })
    end
  end
end
