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
end
