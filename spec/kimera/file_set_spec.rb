# frozen_string_literal: true

require "fileutils"
require "kimera/scope/file_set"
require "tmpdir"

RSpec.describe(Kimera::FileSet) do
  def inside(*files)
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        files.each { |path| touch(path) }
        yield
      end
    end
  end

  def touch(relative)
    FileUtils.mkdir_p(File.dirname(relative))
    File.write(relative, "# x\n")
    relative
  end

  describe "#listed" do
    it "keeps the patterns' order, sorting within each and listing a file once", :aggregate_failures do
      inside("test/helper.rb", "test/b_test.rb", "test/a_test.rb") do
        listed = described_class.new(["test/helper.rb", "test/**/*.rb"]).listed
        expect(listed).to(eq(%w[test/helper.rb test/a_test.rb test/b_test.rb]))
        expect(described_class.new(["test/**/*.rb", "test/helper.rb"]).files)
          .to(eq(%w[test/a_test.rb test/b_test.rb test/helper.rb]))
      end
    end
  end

  describe "#unused" do
    it "returns only the exclude patterns that removed nothing" do
      inside("app/a.rb", "app/legacy/old.rb") do
        noop = described_class.new(["app"], exclude: ["app/legacy/**/*.rb", "app/typo/**/*.rb", "app/a.rb"]).unused
        expect(noop).to(eq(["app/typo/**/*.rb"]))
      end
    end

    it "counts a bare directory exclude as effective" do
      inside("app/a.rb", "app/legacy/old.rb") do
        expect(described_class.new(["app"], exclude: ["app/legacy"]).unused).to(eq([]))
      end
    end

    it "is empty when no excludes were given" do
      inside("app/a.rb") { expect(described_class.new(["app"], exclude: []).unused).to(eq([])) }
    end
  end

  describe "#files" do
    it "expands a directory recursively to its .rb files, sorted and unique" do
      inside("app/a.rb", "app/sub/b.rb", "app/note.txt") do
        expect(described_class.new(["app"]).files).to(eq(["app/a.rb", "app/sub/b.rb"]))
      end
    end

    it "keeps explicit file paths and globs, de-duplicating overlap" do
      inside("lib/x.rb", "lib/y.rb") do
        result = described_class.new(["lib/x.rb", "lib/*.rb"]).files
        expect(result).to(eq(["lib/x.rb", "lib/y.rb"]))
      end
    end

    it "filters a glob to existing .rb files only" do
      inside("a.rb") do
        File.write("a.txt", "x")
        expect(described_class.new(["*.rb", "*.txt"]).files).to(eq(["a.rb"]))
      end
    end

    it "merges the include: patterns into the result" do
      inside("app/a.rb", "extra/b.rb") do
        result = described_class.new(["app"], include: ["extra/b.rb"]).files
        expect(result).to(eq(["app/a.rb", "extra/b.rb"]))
      end
    end

    it "drops files resolved from an exclude path" do
      inside("app/keep.rb", "app/drop.rb") do
        result = described_class.new(["app"], exclude: ["app/drop.rb"]).files
        expect(result).to(eq(["app/keep.rb"]))
      end
    end

    it "drops files matching an exclude glob via fnmatch" do
      inside("app/models/x.rb", "app/legacy/y.rb") do
        result = described_class.new(["app"], exclude: ["app/legacy/**/*.rb"]).files
        expect(result).to(eq(["app/models/x.rb"]))
      end
    end

    it "excludes files via a directory exclude (resolved, not just fnmatched)" do
      inside("app/a.rb", "app/sub/b.rb", "lib/keep.rb") do
        result = described_class.new(%w[app lib], exclude: ["app"]).files
        expect(result).to(eq(["lib/keep.rb"]))
      end
    end

    it "returns everything when the exclude list is empty" do
      inside("a.rb") { expect(described_class.new(["a.rb"], exclude: []).files).to(eq(["a.rb"])) }
    end

    it "accepts a bare String pattern (wrapped via Array)" do
      inside("only.rb") { expect(described_class.new("only.rb").files).to(eq(["only.rb"])) }
    end
  end

  describe Kimera::FileSet::Glob do
    it "finds nothing for a pattern that matches nothing" do
      inside { expect(described_class.new("nope/*.rb").found).to(eq([])) }
    end

    it "covers a file only when the pattern matches its path", :aggregate_failures do
      expect(described_class.new("app/legacy/**/*.rb").covers?("app/legacy/x.rb")).to(be(true))
      expect(described_class.new("app/legacy/**/*.rb").covers?("app/models/x.rb")).to(be(false))
    end
  end

  describe Kimera::FileSet::Exclusion do
    it "drops only the given files its patterns cover", :aggregate_failures do
      inside("app/legacy/y.rb") do
        files = ["app/legacy/y.rb", "app/notes.txt", "app/x.rb"]
        expect(described_class.new(["app/legacy"]).without(files)).to(eq(["app/notes.txt", "app/x.rb"]))
        expect(described_class.new([]).without(files)).to(eq(files))
      end
    end
  end
end
