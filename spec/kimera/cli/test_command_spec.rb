# frozen_string_literal: true

require "kimera/cli"
require "kimera/cli/test_command"

RSpec.describe(Kimera::CLI::TestCommand) do
  def status(success)
    instance_double(Process::Status, success?: success)
  end

  def loading(framework, output: "", success: true)
    command = described_class.new(framework, ["t.rb"], root: "/app")
    allow(Open3).to(receive(:capture2e).and_return([output, status(success)]))
    command.loading
  end

  it "loads minitest files without running them" do
    loading("minitest")
    expect(Open3).to(
      have_received(:capture2e)
      .with("bundle", "exec", "ruby", "-Itest", "-e", described_class::DRY_RUN, "t.rb", chdir: "/app")
    )
  end

  it "loads rspec files with --dry-run" do
    loading("rspec")
    expect(Open3).to(have_received(:capture2e).with("bundle", "exec", "rspec", "--dry-run", "t.rb", chdir: "/app"))
  end

  it "passes when every file loads" do
    expect(loading("rspec")).to(eq(["✓", "Test loading: every test file loads"]))
  end

  it "names the load error when a file fails" do
    result = loading("minitest", output: "t.rb:1: boom (RuntimeError)\n  from x\n", success: false)
    expect(result).to(eq(["✗", "Test loading: t.rb:1: boom (RuntimeError)"]))
  end

  it "warns without failing when Bundler is missing" do
    command = described_class.new("rspec", [], root: "/app")
    allow(Open3).to(receive(:capture2e).and_raise(Errno::ENOENT))
    expect(command.loading).to(eq(["!", "Test loading: Bundler is unavailable; not checked"]))
  end

  it "fails the baseline when Bundler is missing" do
    command = described_class.new("rspec", [], root: "/app")
    allow(Open3).to(receive(:capture2e).and_raise(Errno::ENOENT))
    expect(command.baseline).to(eq(["✗", "Baseline: Bundler is unavailable; run your test suite, then retry"]))
  end
end
