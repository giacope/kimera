# frozen_string_literal: true

require "fileutils"
require "kimera/incremental/git_diff"
require "open3"
require "tmpdir"

RSpec.describe(Kimera::Incremental::GitDiff) do
  def git(*args, dir:)
    out, error, status = Open3.capture3("git", "-C", dir, *args)
    raise(RuntimeError, "git #{args.join(" ")} failed: #{error}") unless status.success?
    out
  end

  let(:dir) { Dir.mktmpdir }

  before do
    git("init", "-q", dir: dir)
    git("config", "user.email", "t@example.com", dir: dir)
    git("config", "user.name", "Test", dir: dir)
    git("config", "commit.gpgsign", "false", dir: dir)
  end

  after { FileUtils.remove_entry(dir) }

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
    it "reports the new-side lines changed since a ref" do
      commit("calc.rb", "def a\n  1\nend\n", "init")
      base = head("HEAD")
      edit("calc.rb", "def a\n  2\n  3\nend\n")
      changed = described_class.new(since: base, root: dir).lines
      expect(changed["calc.rb"]).to(include(2))
    end

    it "raises rather than returning {} when the git command fails (bad ref)" do
      commit("calc.rb", "x = 1\n", "init")
      expect { described_class.new(since: "no-such-ref", root: dir).lines }
        .to(raise_error(Kimera::Incremental::DiffError, /git diff against "no-such-ref" failed \(unknown ref/))
    end

    it "appends no bare paths separator when paths is absent" do
      # A trailing bare `--` would force git to read "calc.rb" as a revision.
      commit("calc.rb", "def a\n  1\nend\n", "init")
      edit("calc.rb", "def a\n  2\nend\n")
      changed = described_class.new(since: "calc.rb", root: dir).lines
      expect(changed["calc.rb"]).to(include(2))
    end

    it "still parses correctly under diff.noprefix (forced a/ b/ prefixes)" do
      git("config", "diff.noprefix", "true", dir: dir) && commit("calc.rb", "def a\n  1\nend\n", "init")
      base = head("HEAD")
      edit("calc.rb", "def a\n  2\n  3\nend\n")
      changed = described_class.new(since: base, root: dir).lines
      expect(changed["calc.rb"]).to(include(2))
    end

    it "emits project-relative paths when root is a subdirectory of the repo" do
      commit("sub/app/calc.rb", "def a\n  1\nend\n", "init")
      base = head("HEAD")
      edit("sub/app/calc.rb", "def a\n  2\nend\n")
      changed = described_class.new(since: base, root: File.join(dir, "sub")).lines
      expect([changed.keys, changed["app/calc.rb"]]).to(match([["app/calc.rb"], include(2)]))
    end

    it "ignores changes outside the root subtree" do
      commit("sub/app/calc.rb", "x = 1\n", "init") && commit("elsewhere.rb", "y = 1\n", "add outside")
      base = head("HEAD~1")
      edit("elsewhere.rb", "y = 2\n")
      changed = described_class.new(since: base, root: File.join(dir, "sub")).lines
      expect(changed).to(eq({}))
    end

    it "scopes to a paths" do
      commit("a.rb", "x = 1\n", "init") && commit("b.rb", "y = 1\n", "add b")
      base = head("HEAD~1")
      edit("a.rb", "x = 2\n") && edit("b.rb", "y = 2\n")
      changed = described_class.new(since: base, root: dir, paths: ["a.rb"]).lines
      expect(changed.keys).to(eq(["a.rb"]))
    end
  end

  describe ".changed_files" do
    it "lists the touched files since a ref" do
      commit("calc.rb", "def a\n  1\nend\n", "init")
      base = head("HEAD")
      edit("calc.rb", "def a\n  9\nend\n")
      expect(described_class.new(since: base, root: dir).files).to(eq(["calc.rb"]))
    end
  end

  describe "#run_diff" do
    it "returns a falsey status when git is unavailable (ENOENT)" do
      previous = ENV.fetch("PATH", nil).tap { ENV["PATH"] = "/nonexistent-dir-for-kimera" }
      out, ok = described_class.new(since: "HEAD", root: dir).__send__(:read)

      expect([out, ok]).to(eq(["", false]))
    ensure
      ENV["PATH"] = previous
    end
  end
end
