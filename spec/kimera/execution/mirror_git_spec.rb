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

  # The project's HEAD and index.
  def state(root) = [test_git(root, "rev-parse", "HEAD"), File.binread(File.join(root, ".git", "index"))]

  # Yields a project, a mirror the project's git was copied into, and the
  # project's state before the copy.
  def mirrored
    Dir.mktmpdir do |root|
      test_project(root)
      before = state(root)
      Dir.mktmpdir do |mirror|
        File.write(File.join(mirror, "calc.rb"), "def a(x, y) = x > y\n")
        described_class.new(root).copy(File.join(mirror, ".git"))
        yield(root, mirror, before)
      end
    end
  end

  # Stages and commits a new file in the mirror.
  def commit_in(mirror)
    File.write(File.join(mirror, "new.rb"), "1\n")
    test_git(mirror, "add", "new.rb")
    test_git(mirror, "-c", "user.name=k", "-c", "user.email=k@k", "commit", "-qm", "two")
  end

  it "lets a suite in the mirror list and read tracked files" do
    mirrored do |_root, mirror|
      expect(test_git(mirror, "ls-files")).to(eq("calc.rb\n"))
      expect(test_git(mirror, "show", "HEAD:calc.rb")).to(eq("def a(x, y) = x > y\n"))
    end
  end

  it "lets a suite in the mirror commit" do
    mirrored do |_root, mirror|
      commit_in(mirror)
      expect(test_git(mirror, "ls-files")).to(eq("calc.rb\nnew.rb\n"))
    end
  end

  it "leaves the project's refs and index untouched" do
    mirrored do |root, mirror, before|
      commit_in(mirror)
      expect(state(root)).to(eq(before))
      expect(test_git(root, "ls-files")).to(eq("calc.rb\n"))
    end
  end

  # What a mirror holds once the root's git was copied into it.
  def copied(root)
    Dir.mktmpdir { |mirror| described_class.new(root).copy(File.join(mirror, ".git")).then { Dir.children(mirror) } }
  end

  it "copies nothing outside a repository" do
    Dir.mktmpdir { |root| expect(copied(root)).to(be_empty) }
  end

  describe "a mirror of the project" do
    # The project's objects, and the mirror's alternates and tracked files once populated.
    def populated
      Dir.mktmpdir do |root|
        test_project(root)
        runner = Kimera::Execution::IsolatedExecution.new(registry: registry, root: root, tests: ["t1"])
        Dir.mktmpdir do |mirror|
          runner.__send__(:populate, mirror)
          alternates = File.read(File.join(mirror, ".git", "objects", "info", "alternates"))
          [File.realpath(File.join(root, ".git", "objects")), alternates, test_git(mirror, "ls-files")]
        end
      end
    end

    it "places the snapshot in the mirror instead of skipping it" do
      objects, alternates, tracked = populated
      expect([alternates, tracked]).to(eq(["#{objects}\n", "calc.rb\n"]))
    end
  end
end
