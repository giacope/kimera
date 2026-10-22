# frozen_string_literal: true

require "json"
require "tmpdir"
require_relative "../property_helper"

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

  # The scan's numbering and anchoring, then what they must be.
  def numbering(source)
    registry = scan(source)
    facts = {
      mutant_ids: registry.each.map { |mutant, _| mutant.id }, point_ids: registry.points.map(&:point_id),
      unanchored: registry.points.reject { |point| anchored?(point, source) }
    }
    [facts, { mutant_ids: (1..registry.count).to_a, point_ids: (1..registry.size).to_a, unanchored: [] }]
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
      expect(described_class.from_h(JSON.parse(registry.to_json)).to_h).to(eq(registry.to_h))
    end
  end

  # How many distinct keys the mutants have and where each resolves, then what they must be.
  def keying(registry)
    keys = registry.keys
    ids = registry.each.map { |mutant, _| mutant.id }
    facts = { distinct: ids.map { |id| keys[id] }.uniq.size, resolved: ids.map { |id| keys.id(keys[id]) } }
    [facts, { distinct: ids.size, resolved: ids }]
  end

  it "keys every mutant uniquely, and each key resolves back to its mutant" do
    for_all(programs, runs: 150) do |program|
      facts, expected = keying(scan(render(program)))
      expect(facts).to(eq(expected), "two mutants share a key, or a key resolves elsewhere")
    end
  end

  def keyed(registry, file) = registry.at(file).flat_map(&:ids).map { |id| registry.keys[id] }

  def written(dir, sources)
    sources.each_with_index.map { |program, i| File.join(dir, "f#{i}.rb").tap { File.write(it, render(program)) } }
  end

  # The files whose keys differ when scanned among the others and alone.
  def drifted(sources)
    Dir.mktmpdir do |dir|
      scanned = ->(paths) { Kimera::RegistryScan.new(operators: operators, root: dir).build(paths) }
      paths = written(dir, sources)
      together = scanned.call(paths)
      paths.map { |path| [File.basename(path), scanned.call([path])] }
        .reject { |file, alone| keyed(together, file) == keyed(alone, file) }.map(&:first)
    end
  end

  # README: a key names the same mutant in a one-file run and in a full one.
  it "keys a file's mutants the same whether it is scanned alone or among others" do
    for_all(Pbt.array(programs, min: 2, max: 4), runs: 40) do |sources|
      expect(drifted(sources)).to(be_empty, "keys depend on the other files")
    end
  end

  def unlined(key) = key.sub(Kimera::MutantKeys::LINE, ":")

  # For each mutant before the shift: how many keys share its key's unlined
  # form after it, and where its key resolves.
  def moves(program, shift)
    before = scan(render(program))
    after = scan(("\n" * shift) + render(program))
    moved = unlined_keys(after)
    before.each.to_h { |mutant, _| [mutant.id, landing(before.keys[mutant.id], moved, after.keys)] }
  end

  def unlined_keys(registry) = registry.each.map { |mutant, _| unlined(registry.keys[mutant.id]) }

  def landing(key, moved, keys) = { unlined: moved.count(unlined(key)), resolved: keys.id(key) }

  # README: a key whose line moved still resolves when path and digest match
  # exactly one mutant. Shifting the file keeps every digest unique, so every
  # old key must come back to its own mutant.
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

  # The embedded values a statement deletion would delete.
  def deleted_embeds(source)
    deletions = scan(source).points.select { |point| point.operator.include?("statement_deletion") }
    deletions.map { |point| [point.location.start_offset, point.location.span] } & embeds(Prism.parse(source).value)
  end

  # README: statement_deletion deletes side-effecting statements; the
  # expression an interpolation embeds is its text, not one of them.
  it "never deletes the value an interpolation embeds" do
    for_all(programs, runs: 150) do |program|
      expect(deleted_embeds(render(program))).to(be_empty)
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

    it "leaves an ambiguous or unknown key unresolved, and reads a number as an id" do
      keys = described_class.new(1 => "a.rb:1:0000000a", 2 => "a.rb:3:0000000a", 3 => "a.rb:2:0000000b")
      tokens = %w[a.rb:2:0000000a a.rb:5:0000000c b.rb:2:0000000b a.rb:7:0000000b 42]
      expect(tokens.map { |token| keys.id(token) })
        .to(eq(["a.rb:2:0000000a", "a.rb:5:0000000c", "b.rb:2:0000000b", 3, 42]))
    end
  end

  # A mutant that is the original can never be killed, and two that are the
  # same program count one test gap twice, whichever operators made them
  # (`x.to_s.to_s` unwrapped or unlinked). A point the parser folds away
  # (the inner `-1` of `--1`) has no program; it is reported unmutatable.
  # A bake Ruby reads a flip-flop or `$_` match in was never the mutated tree:
  # generated programs hold none, so a mutant left a literal in a condition.
  # Per point (its source and labels): whether a bake is the original, how
  # many bakes repeat, and which Ruby misreads.
  def baked(schemata)
    folded = "#{Kimera::MutationPoint::UNMUTATABLE}#{Kimera::Overlay::FileWeave::UNMATCHED}"
    schemata.registry.points.reject { |point| point.unsafe_reason == folded }.map do |point|
      ["#{point.original_source}: #{point.mutants.map(&:label)}", bake_facts(point, schemata)]
    end
  end

  def bake_facts(point, schemata)
    bakes = point.mutants.map { |mutant| schemata.baked(mutant.id) }
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
