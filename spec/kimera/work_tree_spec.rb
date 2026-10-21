# frozen_string_literal: true

require "fileutils"
require "kimera/work_tree"
require "open3"
require "tmpdir"

# R3K8: 171 tracked fixtures vanished during a warm run, and nothing said so.
RSpec.describe(Kimera::WorkTree, :aggregate_failures) do
  def project(git:)
    Dir.mktmpdir("kimera-tree") do |root|
      %w[a.rb b.rb tmp/kimera/report.json log/x.log].each do |path|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), "1\n")
      end
      commit(root) if git
      yield(root)
    end
  end

  def commit(root)
    ["init -q", "add -A", "-c user.email=k@k -c user.name=k commit -qm init"].each do |command|
      Open3.capture2e("git -C #{root} #{command}")
    end
  end

  def changes(root, ignored: [])
    tree = described_class.new(root, ignored: ignored)
    before = tree.snapshot
    yield
    tree.changed(before)
  end

  [true, false].each do |git|
    it "names what a run deleted or rewrote, and nothing else (git: #{git})" do
      project(git: git) do |root|
        changed =
          changes(root) do
            File.delete(File.join(root, "a.rb"))
            File.write(File.join(root, "b.rb"), "22\n")
            File.write(File.join(root, "tmp/kimera/report.json"), "{}")
            File.write(File.join(root, "log/x.log"), "more\n")
          end
        expect(changed).to(eq(%w[a.rb b.rb]))
        expect(changes(root) { :nothing }).to(be_empty)
      end
    end
  end

  it "sees a file already modified before the run change again" do
    project(git: true) do |root|
      File.write(File.join(root, "a.rb"), "dirty\n")
      expect(changes(root) { File.write(File.join(root, "a.rb"), "dirtier!\n") }).to(eq(["a.rb"]))
    end
  end

  it "leaves the files kimera itself writes" do
    project(git: false) do |root|
      report = File.join(root, "report.json")
      expect(changes(root, ignored: [report, nil]) { File.write(report, "{}") }).to(be_empty)
    end
  end

  it "says nothing when nothing changed, and lists at most ten" do
    project(git: false) do |root|
      tree = described_class.new(root)
      expect(tree.watch { :done }).to(eq([:done, nil]))
      (1..12).each { |n| File.write(File.join(root, "f#{n}.rb"), "") }
      expect(tree.watch { File.write(File.join(root, "new.rb"), "") }.last).to(be_nil)
      _, warning = tree.watch { (1..12).each { |n| File.write(File.join(root, "f#{n}.rb"), "changed\n") } }
      expect(warning).to(start_with("kimera: the run changed 12 tracked file(s) in the project"))
      expect(warning.lines.size).to(eq(12))
      expect(warning.lines.last).to(eq("  … and 2 more"))
    end
  end

  it "sees a tracked file of any kind under git, and only Ruby files without it", :aggregate_failures do
    project(git: true) do |root|
      File.write(File.join(root, "fixture.txt"), "x\n")
      commit(root)
      expect(changes(root) { File.delete(File.join(root, "fixture.txt")) }).to(eq(["fixture.txt"]))
    end
    project(git: false) do |root|
      File.write(File.join(root, "fixture.txt"), "x\n")
      expect(changes(root) { File.delete(File.join(root, "fixture.txt")) }).to(be_empty)
    end
  end

  it "leaves what the run writes under tmp, and a directory that only looks like a Ruby file" do
    project(git: false) do |root|
      FileUtils.mkdir_p(File.join(root, "tmp", "cache"))
      File.write(File.join(root, "tmp", "cache", "x.rb"), "1\n")
      FileUtils.mkdir_p(File.join(root, "lib", "odd.rb"))
      changed =
        changes(root) do
          File.write(File.join(root, "tmp", "cache", "x.rb"), "22\n")
          File.write(File.join(root, "lib", "odd.rb", "inside"), "")
        end
      expect(changed).to(be_empty)
    end
  end

  it "compares Ruby files by size and mtime when git is missing" do
    project(git: false) do |root|
      allow(Open3).to(receive(:capture2e).and_raise(Errno::ENOENT))
      expect(changes(root) { File.write(File.join(root, "b.rb"), "22\n") }).to(eq(["b.rb"]))
    end
  end

  it "leaves a tracked file kimera itself writes, such as its report" do
    project(git: true) do |root|
      report = File.join(root, "report.json")
      File.write(report, "{}")
      commit(root)
      expect(changes(root, ignored: [report, nil]) { File.write(report, "{\"x\": 1}") }).to(be_empty)
      expect(changes(root, ignored: [nil]) { File.write(report, "{\"x\": 2}") }).to(eq(["report.json"]))
    end
  end

  it "lists one change without an overflow line" do
    project(git: false) do |root|
      _, warning = described_class.new(root).watch { File.write(File.join(root, "a.rb"), "changed\n") }
      expect(warning.lines.map(&:chomp).last).to(eq("  a.rb"))
    end
  end
end
