# frozen_string_literal: true

require "kimera/execution/isolated"
require "kimera/registry/builder"
require "open3"
require "tmpdir"

# A suite in an isolated mirror can read the project's history (`git
# ls-files`, `git show`) through a private index and refs that borrow the
# project's objects; whatever it writes stays in the mirror.
RSpec.describe(Kimera::Execution::MirrorGit, :aggregate_failures) do
  let(:registry) do
    Kimera::RegistryScan.new.source("def a(x, y)\n  x > y\nend\n", file: "calc.rb")
  end

  def test_git(dir, *arguments)
    out, status = Open3.capture2e("git", *arguments, chdir: dir)
    raise(ArgumentError, "git #{arguments.join(" ")}: #{out}") unless status.success?
    out
  end

  def test_project(root)
    test_git(root, "init", "-q", "-b", "main")
    File.write(File.join(root, "calc.rb"), "def a(x, y) = x > y\n")
    test_git(root, "add", "calc.rb")
    test_git(root, "-c", "user.name=k", "-c", "user.email=k@k", "commit", "-qm", "one")
  end

  it "lets a suite in the mirror list and read tracked files while the project's refs and index stay untouched" do
    Dir.mktmpdir do |root|
      test_project(root)
      before = [test_git(root, "rev-parse", "HEAD"), File.binread(File.join(root, ".git", "index"))]
      Dir.mktmpdir do |mirror|
        File.write(File.join(mirror, "calc.rb"), "def a(x, y) = x > y\n")
        described_class.new(root).copy(File.join(mirror, ".git"))
        expect(test_git(mirror, "ls-files")).to(eq("calc.rb\n"))
        expect(test_git(mirror, "show", "HEAD:calc.rb")).to(eq("def a(x, y) = x > y\n"))
        File.write(File.join(mirror, "new.rb"), "1\n")
        test_git(mirror, "add", "new.rb")
        test_git(mirror, "-c", "user.name=k", "-c", "user.email=k@k", "commit", "-qm", "two")
        expect(test_git(mirror, "ls-files")).to(eq("calc.rb\nnew.rb\n"))
      end
      expect([test_git(root, "rev-parse", "HEAD"), File.binread(File.join(root, ".git", "index"))]).to(eq(before))
      expect(test_git(root, "ls-files")).to(eq("calc.rb\n"))
    end
  end

  it "copies nothing outside a repository" do
    Dir.mktmpdir do |root|
      Dir.mktmpdir do |mirror|
        described_class.new(root).copy(File.join(mirror, ".git"))
        expect(Dir.children(mirror)).to(be_empty)
      end
    end
  end

  describe "a mirror of the project" do
    it "places the snapshot in the mirror instead of skipping it" do
      Dir.mktmpdir do |root|
        test_project(root)
        runner = Kimera::Execution::IsolatedExecution.new(registry: registry, root: root, tests: ["t1"])
        Dir.mktmpdir do |mirror|
          runner.__send__(:populate, mirror)
          expect(File.read(File.join(mirror, ".git", "objects", "info", "alternates")))
            .to(eq("#{File.realpath(File.join(root, ".git", "objects"))}\n"))
          expect(test_git(mirror, "ls-files")).to(eq("calc.rb\n"))
        end
      end
    end
  end
end
