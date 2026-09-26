# frozen_string_literal: true

require "fileutils"
require "kimera/scope/file_set"
require "tmpdir"

RSpec.describe(Kimera::FileSet) do
  let(:dir) { Dir.mktmpdir }

  around do |example|
    Dir.chdir(dir) { example.run }
  ensure
    FileUtils.remove_entry(dir)
  end

  def touch(relative)
    path = File.join(dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, "# x\n")
    relative
  end

  describe ".unused" do
    it "returns only the exclude patterns that removed nothing" do
      touch("app/a.rb")
      touch("app/legacy/old.rb")

      noop = described_class.unused(["app"], ["app/legacy/**/*.rb", "app/typo/**/*.rb", "app/a.rb"])
      expect(noop).to(eq(["app/typo/**/*.rb"]))
    end

    # fnmatch never matches a directory against a file path.
    it "counts a bare directory exclude as effective" do
      touch("app/a.rb")
      touch("app/legacy/old.rb")

      expect(described_class.unused(["app"], ["app/legacy"])).to(eq([]))
    end

    it "is empty when no excludes were given" do
      touch("app/a.rb")
      expect(described_class.unused(["app"], [])).to(eq([]))
    end
  end

  describe ".expand" do
    it "expands a directory recursively to its .rb files, sorted and unique" do
      touch("app/a.rb")
      touch("app/sub/b.rb")
      touch("app/note.txt")

      expect(described_class.expand(["app"])).to(eq(["app/a.rb", "app/sub/b.rb"]))
    end

    it "keeps explicit file paths and globs, de-duplicating overlap" do
      touch("lib/x.rb")
      touch("lib/y.rb")

      result = described_class.expand(["lib/x.rb", "lib/*.rb"])
      expect(result).to(eq(["lib/x.rb", "lib/y.rb"]))
    end

    it "filters a glob to existing .rb files only" do
      touch("a.rb")
      File.write(File.join(dir, "a.txt"), "x")
      expect(described_class.expand(["*.rb", "*.txt"])).to(eq(["a.rb"]))
    end

    it "merges the include: patterns into the result" do
      touch("app/a.rb")
      touch("extra/b.rb")
      result = described_class.expand(["app"], include: ["extra/b.rb"])
      expect(result).to(eq(["app/a.rb", "extra/b.rb"]))
    end

    it "drops files resolved from an exclude path" do
      touch("app/keep.rb")
      touch("app/drop.rb")
      result = described_class.expand(["app"], exclude: ["app/drop.rb"])
      expect(result).to(eq(["app/keep.rb"]))
    end

    it "drops files matching an exclude glob via fnmatch" do
      touch("app/models/x.rb")
      touch("app/legacy/y.rb")
      result = described_class.expand(["app"], exclude: ["app/legacy/**/*.rb"])
      expect(result).to(eq(["app/models/x.rb"]))
    end

    it "excludes files via a directory exclude (resolved, not just fnmatched)" do
      # fnmatch alone would not match "app" against "app/a.rb".
      touch("app/a.rb")
      touch("app/sub/b.rb")
      touch("lib/keep.rb")
      result = described_class.expand(%w[app lib], exclude: ["app"])
      expect(result).to(eq(["lib/keep.rb"]))
    end

    it "returns everything when the exclude list is empty" do
      touch("a.rb")
      expect(described_class.expand(["a.rb"], exclude: [])).to(eq(["a.rb"]))
    end

    it "accepts a bare String pattern (wrapped via Array)" do
      touch("only.rb")
      expect(described_class.expand("only.rb")).to(eq(["only.rb"]))
    end
  end

  describe ".resolve" do
    it "returns [] for a pattern that matches nothing" do
      expect(described_class.resolve("nope/*.rb")).to(eq([]))
    end
  end

  describe ".matches?" do
    it "is true only when a pattern matches the file path", :aggregate_failures do
      expect(described_class.matches?("app/legacy/x.rb", ["app/legacy/**/*.rb"])).to(be(true))
      expect(described_class.matches?("app/models/x.rb", ["app/legacy/**/*.rb"])).to(be(false))
    end
  end
end
