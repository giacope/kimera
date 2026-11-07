# frozen_string_literal: true

require "fileutils"
require "kimera/incremental/selection"
require "kimera/registry/builder"
require "open3"
require "tmpdir"

using PointFields

RSpec.describe(Kimera::Incremental::Selection) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end
  let(:root) { Dir.mktmpdir }

  after { FileUtils.remove_entry(root) }

  def git(*arguments)
    _out, error, status = Open3.capture3("git", "-C", root, *arguments)
    raise(RuntimeError, "git #{arguments.join(" ")} failed: #{error}") unless status.success?
  end

  # calc.rb committed with `x < y` on line 2, then edited to `x > y`.
  def changed
    git("init", "-q", "-b", "main")
    File.write(File.join(root, "calc.rb"), "def a(x, y)\n  x < y\nend\n")
    git("add", "-A")
    git(*%w[-c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false commit -q -m a])
    File.write(File.join(root, "calc.rb"), "def a(x, y)\n  x > y\nend\n")
  end

  describe ".from_diff" do
    it "selects mutants on the lines git reports as changed since the ref, in the root" do
      changed
      ids = described_class.from_diff(since: "main", root: root).ids(registry)
      sources = ids.map { |id| registry.index[id].original_source }.uniq
      expect(sources).to(eq(["x > y"]))
    end

    it "selects nothing when the root has not changed since the ref" do
      changed
      git("checkout", "-q", "--", "calc.rb")
      expect(described_class.from_diff(since: "main", root: root).ids(registry)).to(eq([]))
    end
  end
end
