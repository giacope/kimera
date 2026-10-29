# frozen_string_literal: true

require "fileutils"
require "kimera/cli/run/bench"
require "open3"
require "tmpdir"

RSpec.describe(Kimera::CLI::Run::Bench) do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def git(*arguments)
    _out, error, status = Open3.capture3("git", "-C", dir, *arguments)
    raise(RuntimeError, "git #{arguments.join(" ")} failed: #{error}") unless status.success?
  end

  def identity = %w[-c user.email=t@example.com -c user.name=Test -c commit.gpgsign=false]

  # A repository holding x.rb and y.rb, with x.rb changed since its commit.
  def changed
    git("init", "-q")
    %w[x.rb y.rb].each { |file| File.write(File.join(dir, file), "a = 1\n") }
    git("add", "-A")
    git(*identity, "commit", "-q", "-m", "x")
    File.write(File.join(dir, "x.rb"), "a = 2\n")
  end

  it "scopes a run to the files changed since the ref, in the source root" do
    changed
    change = described_class.new.change("HEAD", dir)
    expect(change.files(%w[x.rb y.rb]) { it }).to(eq(%w[x.rb]))
  end

  it "covers every file without --since" do
    change = described_class.new.change(nil, dir)
    expect(change.files(%w[x.rb y.rb]) { it }).to(eq(%w[x.rb y.rb]))
  end

  it "loads the suite of the run's framework, without the tests whose names it leaves out", :aggregate_failures do
    suite = FakeSuite.new(%w[t1 t2])
    bench = described_class.new(suites: FakeSuites.new(suite))
    expect(bench.suite("rspec", [])).to(equal(suite))
    expect(bench.suite("minitest", ["t2"]).test_ids).to(eq(%w[t1]))
  end

  it "builds the warm harness from the run's settings" do
    harness = FakeHarness.new
    expect(described_class.new(harnesses: harness).harness(jobs: 3).settings).to(eq(jobs: 3))
  end
end
