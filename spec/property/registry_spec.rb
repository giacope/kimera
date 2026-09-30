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

  def unlined(key) = key.sub(Kimera::MutantKeys::LINE, ":")

  # README: a key whose line moved still resolves when path and digest match
  # exactly one mutant. Shifting the file keeps every digest unique, so every
  # old key must come back to its own mutant.
  it "follows a key to its mutant after lines above it move" do
    for_all(programs, Pbt.integer(min: 1, max: 5), runs: 150) do |program, shift|
      before = scan(render(program))
      after = scan(("\n" * shift) + render(program))
      moved = after.each.map { |mutant, _| unlined(after.keys[mutant.id]) }
      before.each.map { |mutant, _| mutant.id }.each do |id|
        key = before.keys[id]
        expect(moved.count(unlined(key))).to(eq(1), "#{key} is not unique once unlined")
        expect(after.keys.id(key)).to(eq(id), "#{key} did not resolve to mutant #{id}")
      end
    end
  end

  # The other outcomes of a lookup, on keys built to collide: an exact key
  # wins, a moved key resolves only when its unlined form is unique, and
  # anything else (ambiguous or unknown) comes back as the text it was.
  describe Kimera::MutantKeys do
    let(:key) do
      parts = Pbt.tuple(Pbt.one_of("a.rb", "b.rb"), Pbt.one_of("1", "2", "3"), Pbt.one_of("0000000a", "0000000b"))
      parts.map(->(fields) { fields.join(":") }, ->(text) { text.split(":") })
    end

    def lookup(keys, token)
      exact = keys.key(token)
      return exact if exact
      matches = keys.select { |_, text| unlined(text) == unlined(token) }.keys
      matches.one? ? matches.first : token
    end

    it "resolves exact keys, unique moved keys, and nothing else" do
      for_all(Pbt.array(key, max: 8), key, runs: 300) do |texts, token|
        keys = texts.uniq.each_with_index.to_h { |text, i| [i + 1, text] }
        expect(described_class.new(keys).id(token)).to(eq(lookup(keys, token)))
      end
    end

    it "leaves an ambiguous or unknown key unresolved, and reads a number as an id", :aggregate_failures do
      keys = described_class.new(1 => "a.rb:1:0000000a", 2 => "a.rb:3:0000000a", 3 => "a.rb:2:0000000b")
      expect(keys.id("a.rb:2:0000000a")).to(eq("a.rb:2:0000000a"))
      expect(keys.id("a.rb:5:0000000c")).to(eq("a.rb:5:0000000c"))
      expect(keys.id("b.rb:2:0000000b")).to(eq("b.rb:2:0000000b"))
      expect(keys.id("a.rb:7:0000000b")).to(eq(3))
      expect(keys.id("42")).to(eq(42))
    end
  end

  # A mutant that is the original can never be killed, and two that are the
  # same program count one test gap twice, whichever operators made them
  # (`x.to_s.to_s` unwrapped or unlinked). A point the parser folds away
  # (the inner `-1` of `--1`) has no program; it is reported unmutatable.
  it "never emits a mutant that is the original program, or two that are the same program" do
    for_all(programs, runs: 60) do |program|
      schemata = SchemataProjection.check(render(program))
      schemata.registry.points.each do |point|
        next if point.unsafe_reason == "#{Kimera::MutationPoint::UNMUTATABLE}#{Kimera::Overlay::FileWeave::UNMATCHED}"
        bakes = point.mutants.map { |mutant| schemata.baked(mutant.id) }
        source = point.original_source
        expect(bakes).not_to(include(schemata.original), "#{source}: a mutant is the original")
        expect(bakes).to(eq(bakes.uniq), "#{source}: #{point.mutants.map(&:label)} repeat a program")
      end
    end
  end
end
