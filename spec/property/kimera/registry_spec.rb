# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../property_helper"

using PointFields

RSpec.describe(Kimera::Registry) do
  def unmatched = "no node to guard: kimera found nothing of its kind where the point was scanned"

  let(:programs) { RubyPrograms.new(depth: 2) }
  let(:operators) { Kimera::Operators.build(keys: ["all"]) }

  def scan(source, file: "x.rb") = Kimera::RegistryScan.new(operators: operators).source(source, file: file)

  def render(program) = RubyPrograms.render(program)

  def anchored?(point, source)
    location = point.location.to_h
    start = location.fetch("start_offset")
    source.byteslice(start, location.fetch("length")) == point.original_source &&
      source.byteslice(0, start).count("\n") + 1 == location.fetch("start_line")
  end

  def numbering(source)
    registry = scan(source)
    facts = {
      mutant_ids: registry.each.map { |mutant, _| mutant.to_i }, point_ids: registry.to_a.map(&:point_id),
      unanchored: registry.to_a.reject { |point| anchored?(point, source) }
    }
    [facts, { mutant_ids: (1..registry.each.count).to_a, point_ids: (1..registry.to_a.size).to_a, unanchored: [] }]
  end

  it "numbers mutants and points 1..n in scan order and anchors each point at its exact source" do
    for_all(programs, runs: 150) do |program|
      facts, expected = numbering(render(program))
      expect(facts).to(eq(expected))
    end
  end

  it "round-trips through its JSON form" do
    for_all(programs, runs: 150) do |program|
      registry = scan(render(program))
      expect(JSON.parse(described_class.parse(registry.to_json).to_json)).to(eq(JSON.parse(registry.to_json)))
    end
  end

  def keying(registry)
    keys = Kimera::MutantKeys.of(registry)
    ids = registry.each.map { |mutant, _| mutant.to_i }
    facts = { distinct: ids.map { |id| keys[id] }.uniq.size, resolved: ids.map { |id| keys.id(keys[id]) } }
    [facts, { distinct: ids.size, resolved: ids }]
  end

  it "keys every mutant uniquely, and each key resolves back to its mutant" do
    for_all(programs, runs: 150) do |program|
      facts, expected = keying(scan(render(program)))
      expect(facts).to(eq(expected), "two mutants share a key, or a key resolves elsewhere")
    end
  end

  def keyed(registry, file)
    keys = Kimera::MutantKeys.of(registry)
    registry.to_h.fetch(file, []).flat_map(&:ids).map { |id| keys[id] }
  end

  def written(dir, sources)
    sources.each_with_index.map { |program, i| File.join(dir, "f#{i}.rb").tap { File.write(it, render(program)) } }
  end

  def drifted(sources)
    Dir.mktmpdir do |dir|
      scanned = ->(paths) { Kimera::RegistryScan.new(operators: operators, root: dir).build(paths) }
      paths = written(dir, sources)
      together = scanned.call(paths)
      paths.map { |path| [File.basename(path), scanned.call([path])] }
        .reject { |file, alone| keyed(together, file) == keyed(alone, file) }.map(&:first)
    end
  end

  it "keys a file's mutants the same whether it is scanned alone or among others" do
    for_all(Pbt.array(programs, min: 2, max: 4), runs: 40) do |sources|
      expect(drifted(sources)).to(be_empty, "keys depend on the other files")
    end
  end

  def unlined(key) = key.sub(Kimera::MutantKeys::LINE, ":")

  def moves(program, shift)
    before = scan(render(program))
    after = scan(("\n" * shift) + render(program))
    moved = unlined_keys(after)
    earlier, later = [before, after].map { Kimera::MutantKeys.of(it) }
    before.each.to_h { |mutant, _| [mutant.to_i, landing(earlier[mutant.to_i], moved, later)] }
  end

  def unlined_keys(registry)
    keys = Kimera::MutantKeys.of(registry)
    registry.each.map { |mutant, _| unlined(keys[mutant.to_i]) }
  end

  def landing(key, moved, keys) = { unlined: moved.count(unlined(key)), resolved: keys.id(key) }

  it "follows a key to its mutant after lines above it move" do
    for_all(programs, Pbt.integer(min: 1, max: 5), runs: 150) do |program, shift|
      found = moves(program, shift)
      expect(found).to(eq(found.to_h { |id, _| [id, { unlined: 1, resolved: id }] }))
    end
  end

  def embeds(node)
    values = node.compact_child_nodes.flat_map { embeds(it) }
    return values unless node.is_a?(Prism::EmbeddedStatementsNode) && node.statements
    values << node.statements.body.last.location.then { [it.start_offset, it.length] }
  end

  def deleted_embeds(source)
    deletions = scan(source).to_a.select { |point| point.operator.include?("statement_deletion") }
    spans = deletions.map { |point| point.location.to_h.values_at("start_offset", "length") }
    spans & embeds(Prism.parse(source).value)
  end

  it "never deletes the value an interpolation embeds" do
    for_all(programs, runs: 150) do |program|
      expect(deleted_embeds(render(program))).to(be_empty)
    end
  end

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

    it "leaves an ambiguous or unknown key unresolved, and reads a number as an id" do
      keys = described_class.new(1 => "a.rb:1:0000000a", 2 => "a.rb:3:0000000a", 3 => "a.rb:2:0000000b")
      tokens = %w[a.rb:2:0000000a a.rb:5:0000000c b.rb:2:0000000b a.rb:7:0000000b 42]
      expect(tokens.map { |token| keys.id(token) })
        .to(eq(["a.rb:2:0000000a", "a.rb:5:0000000c", "b.rb:2:0000000b", 3, 42]))
    end
  end

  def baked(schemata)
    folded = "#{Kimera::Reason::UNMUTATABLE}#{unmatched}"
    schemata.registry.to_a.reject { |point| point.reasons(Kimera::Reason.unsafety).first == folded }.map do |point|
      ["#{point.original_source}: #{point.mutants.map(&:to_s)}", bake_facts(point, schemata)]
    end
  end

  def bake_facts(point, schemata)
    bakes = point.mutants.map { |mutant| schemata.baked(mutant.to_i) }
    misread = bakes.map(&:inspect).grep(/flipflop|match_current_line/)
    { original: bakes.include?(schemata.original), repeated: bakes.size - bakes.uniq.size, misread: misread }
  end

  it "never emits a mutant that is the original program, two that are the same program, or one it misreads" do
    for_all(programs, runs: 60) do |program|
      facts = baked(SchemataProjection.check(render(program)))
      expect(facts).to(eq(facts.map { |point, _| [point, { original: false, repeated: 0, misread: [] }] }))
    end
  end
end
