# frozen_string_literal: true

require "open3"
require "tmpdir"
require "kimera/incremental/selection"
require_relative "property_helper"

# `kimera changed` and `--since` mutate only the lines a diff touched: a
# changed line the parser misses is a mutant silently left out of the gate.
RSpec.describe(Kimera::Incremental::GitDiff) do
  # Content can read as a header once rendered after its "+": "++ b/x"
  # becomes "+++ b/x".
  let(:text) do
    Pbt.one_of("x = 1", "y = 2", "end", "", "  z", "# note", "@@ -1 +1 @@", "+++ a/x", "--- b/y", "++ b/c.rb")
  end
  let(:changes) do
    Pbt.array(Pbt.tuple(Pbt.one_of("app/a.rb", "lib/b c.rb", "c.rb"), Pbt.array(Pbt.integer(min: 1, max: 40))), max: 3)
  end

  # What `git diff --unified=0` prints for these added lines, with a
  # removal-only hunk and a deleted file as noise that must add nothing.
  def render(changed, random)
    "#{changed.map { |file, lines| section(file, lines, random) }.join}" \
      "diff --git a/old.rb b/old.rb\n--- a/old.rb\n+++ /dev/null\n@@ -1 +0,0 @@\n-x\n"
  end

  def section(file, lines, random)
    "diff --git a/#{file} b/#{file}\n--- a/#{file}\n+++ b/#{file}\n@@ -90,2 +80,0 @@\n-gone\n-gone\n" \
      "#{lines.sort.slice_when { |a, b| b != a + 1 }.map { |run| hunk(run, random) }.join}"
  end

  def hunk(run, random)
    count = run.one? && random.rand(2).zero? ? "" : ",#{run.size}"
    "@@ -#{run.first},1 +#{run.first}#{count} @@ def m\n-old\n#{run.map { "+#{text.generate(random)}\n" }.join}"
  end

  it "parses a rendered diff back to exactly the added lines" do
    for_all(changes, Pbt.integer, runs: 200) do |changed, seed|
      files = changed.uniq(&:first)
      parsed = described_class.parse(render(files, Random.new(seed)))
      expect(parsed.transform_values { |set| set.to_a.sort })
        .to(eq(files.reject { |_, lines| lines.empty? }.to_h { |file, lines| [file, lines.uniq.sort] }))
    end
  end

  # Against git itself: after any edit, the lines the parser does not report
  # must be lines the old file already had, in order. A new or edited line
  # can never go unreported.
  describe "on a real repository" do
    let(:lines) { Pbt.array(Pbt.one_of("a", "b", "c", "d", "end", "++ b/g.rb"), max: 12) }

    def git(dir, *)
      out, status = Open3.capture2e("git", "-C", dir, "-c", "user.name=k", "-c", "user.email=k@k", *)
      raise(Kimera::Error, out) unless status.success?
    end

    def committed(dir, old)
      File.write(File.join(dir, "f.rb"), old.map { "#{it}\n" }.join)
      git(dir, "init", "-q")
      git(dir, "add", ".")
      git(dir, "commit", "-q", "-m", "base", "--allow-empty")
    end

    def edited(old, new)
      Dir.mktmpdir do |dir|
        committed(dir, old)
        File.write(File.join(dir, "f.rb"), new.map { "#{it}\n" }.join)
        described_class.new(since: "HEAD", root: dir).lines.fetch("f.rb", Set.new)
      end
    end

    # The oracle below is only as good as this check.
    it "judges subsequences exactly", :aggregate_failures do
      expect(Subsequence.of?([], [])).to(be(true))
      expect(Subsequence.of?([], %w[a])).to(be(true))
      expect(Subsequence.of?(%w[a], [])).to(be(false))
      expect(Subsequence.of?(%w[a c], %w[a b c])).to(be(true))
      expect(Subsequence.of?(%w[z], %w[a b])).to(be(false))
      expect(Subsequence.of?(%w[b a], %w[a b])).to(be(false))
      expect(Subsequence.of?(%w[a a], %w[a])).to(be(false))
      expect(Subsequence.of?(%w[a a], %w[a b a])).to(be(true))
    end

    it "reports a line an edit inserts" do
      expect(edited(%w[a b], %w[a z b]).to_a).to(eq([2]))
    end

    it "reports every line that is not an unchanged line of the old file" do
      for_all(lines, lines, runs: 40) do |old, new|
        reported = edited(old, new)
        expect(reported.to_a - (1..new.size).to_a).to(be_empty, "reported lines beyond the file")
        kept = new.each_with_index.reject { |_, i| reported.include?(i + 1) }.map(&:first)
        expect(Subsequence.of?(kept, old)).to(be(true), "unreported #{kept} are not old lines in order")
      end
    end
  end

  describe Kimera::Incremental::Selection do
    def expected(registry, touched)
      registry.points.select { |point| point.location.range.any? { touched.include?(it) } }.flat_map(&:ids)
    end

    it "selects, in registry order, exactly the mutants on a changed line" do
      for_all(RubyPrograms.new(depth: 2), Pbt.array(Pbt.integer(min: 1, max: 8)), runs: 150) do |program, lines|
        registry = Kimera::RegistryScan.new.source(RubyPrograms.render(program), file: "x.rb")
        touched = Set.new(lines)
        expect(described_class.select(registry, { "x.rb" => touched, "other.rb" => Set.new(1..8) }))
          .to(eq(expected(registry, touched)))
      end
    end
  end
end
