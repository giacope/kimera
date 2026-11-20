# frozen_string_literal: true

require "fileutils"
require "kimera/incremental/git_diff"
require "open3"
require "tmpdir"

RSpec.describe(Kimera::Incremental::GitDiff) do
  def git(*arguments, dir:)
    out, error, status = Open3.capture3("git", "-C", dir, *arguments)
    raise(RuntimeError, "git #{arguments.join(" ")} failed: #{error}") unless status.success?
    out
  end

  def repository(&)
    Dir.mktmpdir do |dir|
      git("init", "-q", dir: dir)
      git("config", "user.email", "t@example.com", dir: dir)
      git("config", "user.name", "Test", dir: dir)
      git("config", "commit.gpgsign", "false", dir: dir)
      Dir.chdir(dir, &)
    end
  end

  def dir = Dir.pwd

  def commit(path, body, message)
    path = File.join(dir, path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    git("add", "-A", dir: dir)
    git("commit", "-q", "-m", message, dir: dir)
  end

  def edit(path, body)
    File.write(File.join(dir, path), body)
  end

  def head(rev = "HEAD")
    git("rev-parse", rev, dir: dir).strip
  end

  describe ".changed_lines" do
    def since(path, before, after, root: dir)
      commit(path, before, "init")
      base = head("HEAD")
      edit(path, after)
      described_class.new(since: base, root: root).lines
    end

    it "reports the new-side lines changed since a ref" do
      changed = repository { since("calc.rb", "def a\n  1\nend\n", "def a\n  2\n  3\nend\n") }
      expect(changed["calc.rb"]).to(include(2))
    end

    def branched
      commit("calc.rb", "a = 1\nb = 1\nc = 1\n", "init")
      git("branch", "-q", "feature", dir: dir)
      commit("calc.rb", "a = 1\nb = 2\nc = 1\n", "main moves on")
      git("rev-parse", "--abbrev-ref", "HEAD", dir: dir).strip.tap do
        git("checkout", "-q", "feature", dir: dir)
        commit("calc.rb", "a = 2\nb = 1\nc = 1\n", "feature")
        edit("calc.rb", "a = 2\nb = 1\nc = 3\n")
      end
    end

    it "diffs against the merge-base with the ref, keeping uncommitted work" do
      changed = repository { described_class.new(since: branched, root: dir).lines }
      expect(changed["calc.rb"].to_a).to(eq([1, 3]))
    end

    it "raises rather than returning {} when the git command fails (bad ref)" do
      repository do
        commit("calc.rb", "x = 1\n", "init")
        expect { described_class.new(since: "no-such-ref", root: dir).lines }
          .to(raise_error(Kimera::Incremental::DiffError, /git diff against "no-such-ref" failed \(unknown ref/))
      end
    end

    def shallow
      commit("calc.rb", "x = 1\n", "init")
      commit("calc.rb", "x = 2\n", "next")
      File.join(dir, "shallow").tap { |clone| git("clone", "-q", "--depth", "1", "file://#{dir}", clone, dir: dir) }
    end

    def broken(pattern) = raise_error(Kimera::Incremental::DiffError, pattern)

    it "names a shallow clone as the likely cause of a missing ref, and only then", :aggregate_failures do
      repository do
        expect { described_class.new(since: "origin/nope", root: shallow).lines }
          .to(broken(/git missing\); this clone is shallow, so fetch the base ref/))
        expect { described_class.new(since: "nope", root: dir).lines }.to(broken(/git missing\)\z/))
      end
    end

    def unseparated
      commit("calc.rb", "def a\n  1\nend\n", "init")
      edit("calc.rb", "def a\n  2\nend\n")
      described_class.new(since: "calc.rb", root: dir).lines
    end

    it "appends no bare paths separator when paths is absent" do
      expect(repository { unseparated }["calc.rb"]).to(include(2))
    end

    def unprefixed
      git("config", "diff.noprefix", "true", dir: dir)
      since("calc.rb", "def a\n  1\nend\n", "def a\n  2\n  3\nend\n")
    end

    it "still parses correctly under diff.noprefix (forced a/ b/ prefixes)" do
      expect(repository { unprefixed }["calc.rb"]).to(include(2))
    end

    def nested = since("sub/app/calc.rb", "def a\n  1\nend\n", "def a\n  2\nend\n", root: File.join(dir, "sub"))

    it "emits project-relative paths when root is a subdirectory of the repo" do
      changed = repository { nested }
      expect([changed.keys, changed["app/calc.rb"]]).to(match([["app/calc.rb"], include(2)]))
    end

    def outside
      commit("sub/app/calc.rb", "x = 1\n", "init") && commit("elsewhere.rb", "y = 1\n", "add outside")
      base = head("HEAD~1")
      edit("elsewhere.rb", "y = 2\n")
      described_class.new(since: base, root: File.join(dir, "sub")).lines
    end

    it "ignores changes outside the root subtree" do
      expect(repository { outside }).to(eq({}))
    end

    def scoped
      commit("a.rb", "x = 1\n", "init") && commit("b.rb", "y = 1\n", "add b")
      base = head("HEAD~1")
      edit("a.rb", "x = 2\n") && edit("b.rb", "y = 2\n")
      described_class.new(since: base, root: dir, paths: ["a.rb"]).lines
    end

    it "scopes to a paths" do
      expect(repository { scoped }.keys).to(eq(["a.rb"]))
    end
  end

  describe ".changed_files" do
    def touched
      commit("calc.rb", "def a\n  1\nend\n", "init")
      base = head("HEAD")
      edit("calc.rb", "def a\n  9\nend\n")
      described_class.new(since: base, root: dir).files
    end

    it "lists the touched files since a ref" do
      expect(repository { touched }).to(eq(["calc.rb"]))
    end
  end

  describe "#names" do
    def pruned
      commit("a.rb", "x = 1\ny = 2\n", "init")
      commit("b.rb", "z = 1\n", "b")
      head("HEAD").tap do
        edit("a.rb", "x = 1\n")
        FileUtils.rm(File.join(dir, "b.rb"))
        edit("c.rb", "w = 1\n")
        git("add", "c.rb", dir: dir)
      end
    end

    it "names every file changed since the ref, deleted ones and ones that only lost lines included" do
      expect(repository { described_class.new(since: pruned, root: dir).names }).to(eq(%w[a.rb b.rb c.rb]))
    end
  end

  describe "#run_diff" do
    it "fails a name listing as a diff error, not ENOENT, when git is unavailable" do
      previous = ENV.fetch("PATH", nil).tap { ENV["PATH"] = "/nonexistent-dir-for-kimera" }
      expect { described_class.new(since: "HEAD", root: Dir.tmpdir).names }.to(raise_error(Kimera::Incremental::DiffError))
    ensure
      ENV["PATH"] = previous
    end

    it "fails without a shallow-clone hint when git itself is missing" do
      previous = ENV.fetch("PATH", nil).tap { ENV["PATH"] = "/nonexistent-dir-for-kimera" }
      expect { described_class.new(since: "HEAD", root: Dir.tmpdir).lines }
        .to(raise_error(Kimera::Incremental::DiffError, /git missing\)\z/))
    ensure
      ENV["PATH"] = previous
    end
  end
end
