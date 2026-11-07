# frozen_string_literal: true

require_relative "../property_helper"

RSpec.describe(Kimera::Overlay) do
  let(:programs) { RubyPrograms.new(depth: 2) }

  def render(program) = RubyPrograms.render(program)

  def explain(mismatches)
    id, got, want = mismatches.first
    "mutant #{id} reduces to\n#{got.inspect}\nbut its bake is\n#{want.inspect}"
  end

  def every_id(registry) = registry.each.map { |mutant, _| mutant.to_i }

  def expect_reduced(schemata)
    mismatches = schemata.mismatches
    said = -> { mismatches.empty? ? "with no mutant active, the program changed" : explain(mismatches) }
    expect([mismatches, schemata.projected(nil)]).to(eq([[], schemata.original]), said)
  end

  def accounted(schemata)
    ids, skipped = schemata.result.to_h.values_at(:mutant_ids, :skipped_unsafe)
    applied = ids.sort
    reported = (applied + skipped).sort
    expect(applied: applied, guarded: schemata.guards.uniq.sort, reported: reported)
      .to(eq(accounting(applied, schemata.registry)))
  end

  def accounting(applied, registry)
    { applied: applied.uniq, guarded: applied.uniq, reported: every_id(registry).sort }
  end

  it "is each mutant when it is active and the original when none is, and guards every mutant it reports" do
    for_all(programs, runs: 100) do |program|
      schemata = SchemataProjection.check(render(program))
      expect_reduced(schemata)
      accounted(schemata)
    end
  end

  describe "running a flipped mutant" do
    let(:inputs) do
      values = [-3, -1, 0, 1, 2, 5, nil, "4"]
      Pbt.array(Pbt.tuple(Pbt.array(Pbt.one_of(*values), max: 3), Pbt.one_of(:omitted, *values)), min: 1, max: 5)
    end

    def outcome(receiver, (positional, keyword))
      [:returned, plain(receiver.m(*positional, **(keyword == :omitted ? {} : { c: keyword })))]
    rescue StandardError => error
      [:raised, error.class, SchemataProjection.worded(error)]
    end

    def plain(value) = value.instance_of?(Object) ? Object : value

    def loaded(source)
      Object.new.extend(Module.new.tap { |mod| Kimera::Warnings.silenced.during { mod.module_eval(source) } })
    end

    def flipped(live, id, calls)
      live.instance_variables.each { |name| live.remove_instance_variable(name) }
      Kimera::RUNTIME.during(id) { calls.map { |call| outcome(live, call) } }
    end

    def unlike_bakes(schemata, calls)
      live = loaded(schemata.result.to_s)
      schemata.result.to_h.fetch(:mutant_ids).reject do |id|
        bake = loaded(schemata.overlay.bake("x.rb", schemata.source, id))
        flipped(live, id, calls) == calls.map { |call| outcome(bake, call) }
      end
    end

    it "behaves exactly like its bake on every input" do
      for_all(programs, inputs, runs: 40) do |program, calls|
        expect(unlike_bakes(SchemataProjection.check(render(program)), calls)).to(be_empty)
      end
    end
  end

  it "reduces to each bake across real files" do
    root = File.expand_path("../../..", __dir__)
    sample(Dir[File.join(root, "{lib,examples}/**/*.rb")], (6 * PropertyRuns::SCALE).ceil).each do |path|
      mismatches = SchemataProjection.check(File.read(path, encoding: Encoding::UTF_8)).mismatches
      expect(mismatches).to(be_empty, -> { "#{path}: #{explain(mismatches)}" })
    end
  end
end
