# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "property_helper"

RSpec.describe(Kimera::Registry) do
  let(:programs) { RubyPrograms.new(depth: 2) }
  let(:operators) { Kimera::Operators.build(keys: ["all"]) }

  def scan(source, file: "x.rb") = Kimera::RegistryScan.new(operators: operators).source(source, file: file)

  def render(program) = RubyPrograms.render(program)

  def anchored?(point, source)
    location = point.location
    source.byteslice(location.start_offset, location.span) == point.original_source &&
      source.byteslice(0, location.start_offset).count("\n") + 1 == location.start_line
  end

  it "numbers mutants and points 1..n in scan order and anchors each point at its exact source" do
    for_all(programs, runs: 150) do |program|
      source = render(program)
      registry = scan(source)
      expect(registry.each.map { |mutant, _| mutant.id }).to(eq((1..registry.count).to_a))
      expect(registry.points.map(&:point_id)).to(eq((1..registry.size).to_a))
      expect(registry.points.reject { |point| anchored?(point, source) }).to(be_empty)
    end
  end

  it "round-trips through its JSON form" do
    for_all(programs, runs: 150) do |program|
      registry = scan(render(program))
      expect(described_class.from_h(JSON.parse(registry.to_json)).to_h).to(eq(registry.to_h))
    end
  end

  it "keys every mutant uniquely, and each key resolves back to its mutant" do
    for_all(programs, runs: 150) do |program|
      registry = scan(render(program))
      keys = registry.keys
      ids = registry.each.map { |mutant, _| mutant.id }
      expect(ids.map { |id| keys[id] }.uniq.size).to(eq(ids.size), "two mutants share a key")
      expect(ids.map { |id| keys.id(keys[id]) }).to(eq(ids))
    end
  end

  def keyed(registry, file) = registry.at(file).flat_map(&:ids).map { |id| registry.keys[id] }

  def written(dir, sources)
    sources.each_with_index.map { |program, i| File.join(dir, "f#{i}.rb").tap { File.write(it, render(program)) } }
  end

  # README: a key names the same mutant in a one-file run and in a full one.
  it "keys a file's mutants the same whether it is scanned alone or among others" do
    for_all(Pbt.array(programs, min: 2, max: 4), runs: 40) do |sources|
      Dir.mktmpdir do |dir|
        paths = written(dir, sources)
        together = Kimera::RegistryScan.new(operators: operators, root: dir).build(paths)
        paths.each do |path|
          alone = Kimera::RegistryScan.new(operators: operators, root: dir).build([path])
          file = File.basename(path)
          expect(keyed(together, file)).to(eq(keyed(alone, file)), "#{file}: keys depend on the other files")
        end
      end
    end
  end

  # A key whose line moved still resolves when path and digest match exactly
  # one mutant, and never resolves to a different mutant.
  it "follows a key to its mutant after lines above it move" do
    for_all(programs, Pbt.integer(min: 1, max: 5), runs: 150) do |program, shift|
      before = scan(render(program))
      after = scan(("\n" * shift) + render(program))
      before.each.map { |mutant, _| mutant.id }.each do |id|
        key = before.keys[id]
        expect(after.keys.id(key)).to(eq(id).or(be_a(String)), "#{key} resolved to another mutant")
      end
    end
  end

  # A mutant that is the original can never be killed, and two of one kind
  # that are the same program count one test gap twice. (Different kinds can
  # still meet on redundant code: `x.to_s.to_s` unwrapped or unlinked.)
  it "never emits a mutant that is the original program, or two of one kind that are the same program" do
    for_all(programs, runs: 60) do |program|
      schemata = SchemataProjection.check(render(program))
      schemata.registry.points.each do |point|
        bakes = point.mutants.map { |mutant| [mutant.directive["type"], schemata.baked(mutant.id)] }
        source = point.original_source
        expect(bakes.map(&:last)).not_to(include(schemata.original), "#{source}: a mutant is the original")
        expect(bakes).to(eq(bakes.uniq), "#{source}: #{point.mutants.map(&:label)} repeat a program")
      end
    end
  end
end
