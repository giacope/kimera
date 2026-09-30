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
    command = ["bundle", "exec", "ruby", "-Itest", "-e", described_class::DRY_RUN, "t.rb"]
    expect(Open3).to(have_received(:capture2e).with({ "KIMERA" => "1" }, *command, chdir: "/app"))
  end

  it "loads rspec files with --dry-run" do
    loading("rspec")
    expect(Open3).to(
      have_received(:capture2e).with({ "KIMERA" => "1" }, "bundle", "exec", "rspec", "--dry-run", "t.rb", chdir: "/app")
    )
  end

  # A helper gating its coverage floor on KIMERA must not fail the dry run,
  # which executes no code at all.
  it "runs the full baseline with KIMERA set too" do
    command = described_class.new("rspec", ["t.rb"], root: "/app")
    allow(Open3).to(receive(:capture2e).and_return(["", status(true)]))
    command.baseline
    expect(Open3).to(
      have_received(:capture2e).with(
        { "KIMERA" => "1" }, "bundle", "exec", "rspec", "t.rb",
        chdir: "/app"
    )
    )
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

  def baseline(framework, output)
    command = described_class.new(framework, ["t.rb"], root: "/app")
    allow(Open3).to(receive(:capture2e).and_return([output, status(false)]))
    command.baseline.last
  end

  it "names the failing RSpec examples in a red baseline" do
    output = <<~OUT
      2 examples, 2 failures

      Failed examples:

      rspec ./spec/a_spec.rb:3 # A adds
      rspec ./spec/b_spec.rb:9 # B subtracts
    OUT
    expect(baseline("rspec", output)).to(
      eq(
        "Baseline: 2 examples, 2 failures (fix it, then rerun `kimera doctor --check-baseline`)\n  " \
          "failing tests:\n    ./spec/a_spec.rb:3\n    ./spec/b_spec.rb:9"
      )
    )
  end

  it "names the failing Minitest tests, failures and errors alike" do
    output = <<~OUT
        1) Failure:
      CalcTest#test_add [test/calc_test.rb:5]:
      Expected: 3

        2) Error:
      CalcTest#test_0001_divides by zero:
      ZeroDivisionError: divided by 0

      2 runs, 2 assertions, 1 failures, 1 errors, 0 skips
    OUT
    listed = "failing tests:\n    CalcTest#test_add\n    CalcTest#test_0001_divides by zero"
    expect(baseline("minitest", output)).to(end_with(listed))
  end

  # Rails' minitest reporter prints its headers unnumbered (once-campfire).
  it "names the failing tests of a Rails minitest run" do
    output = <<~OUT
      Failure:
      ComposerTest#test_attach [test/system/composer_test.rb:9]:
      Expected true

      Error:
      WebhookTest#test_delivers:
      JSON::ParserError: unexpected end of input

      2 runs, 1 assertions, 1 failures, 1 errors, 0 skips
    OUT
    listed = "failing tests:\n    ComposerTest#test_attach\n    WebhookTest#test_delivers"
    expect(baseline("minitest", output)).to(end_with(listed))
  end

  # rubocop-ast needs a generated lexer; the count line alone said nothing.
  it "names the error that stopped the suite before any example ran" do
    output = <<~OUT
      An error occurred while loading spec_helper.
      LoadError:
        cannot load such file -- lib/lexer.rex
      # ./lib/lexer.rb:4

      0 examples, 0 failures, 1 error occurred outside of examples
    OUT
    cause = "(LoadError: cannot load such file -- lib/lexer.rex)"
    expect(loading("rspec", output: output, success: false).last).to(end_with("outside of examples #{cause}"))
  end

  # thor's spec/helper.rb sets minimum_coverage(90), which a dry run always trips.
  it "explains a command that failed with no failing test", :aggregate_failures do
    expect(loading("rspec", output: "911 examples, 0 failures\n", success: false).last)
      .to(eq("Test loading: 911 examples, 0 failures#{described_class::QUIET_EXIT}"))
    expect(baseline("minitest", "5 runs, 9 assertions, 0 failures, 0 errors, 0 skips\n"))
      .to(include(described_class::QUIET_EXIT))
  end

  it "adds no cause to a red baseline whose failures are its own", :aggregate_failures do
    output = "RSpec::Expectations::ExpectationNotMetError:\n  expected 1\n\n2 examples, 1 failure\n"
    expect(baseline("rspec", output)).to(start_with("Baseline: 2 examples, 1 failure (fix it"))
  end

  it "lists at most ten failing tests" do
    output = (1..12).map { |n| "rspec ./spec/a_spec.rb:#{n} # a" }.join("\n")
    listed = baseline("rspec", output)
    expect(listed).to(include("./spec/a_spec.rb:10\n    … and 2 more"))
  end

  it "keeps the summary alone when no test ids can be read" do
    expect(baseline("rspec", "LoadError\n"))
      .to(eq("Baseline: LoadError (fix it, then rerun `kimera doctor --check-baseline`)"))
  end

  it "fails the baseline when Bundler is missing" do
    command = described_class.new("rspec", [], root: "/app")
    allow(Open3).to(receive(:capture2e).and_raise(Errno::ENOENT))
    expect(command.baseline).to(eq(["✗", "Baseline: Bundler is unavailable; run your test suite, then retry"]))
  end

  def parallel(framework, outputs)
    command = described_class.new(framework, ["t.rb"], root: "/app")
    shards = outputs.each_index.map { |index| Kimera::CLI::TestShard.argv(framework, index, outputs.size) }
    allow(Open3).to(receive(:capture2e)) do |_env, *argv, **|
      output = outputs[shards.index { |shard| argv.each_cons(shard.size).include?(shard) }]
      [output, status(output.empty?)]
    end
    command.parallel(outputs.size)
  end

  def shard(framework, index, count)
    [{ "KIMERA" => "1" }, "bundle", "exec", "ruby", *Kimera::CLI::TestShard.argv(framework, index, count), "t.rb"]
  end

  it "runs one process per worker, each on its share of the tests", :aggregate_failures do
    expect(parallel("rspec", ["", ""])).to(eq(["✓", "Parallel baseline: green split across 2 processes too (jobs: 2)"]))
    [0, 1].each { |index| expect(Open3).to(have_received(:capture2e).with(*shard("rspec", index, 2), chdir: "/app")) }
    parallel("minitest", ["", "", ""])
    expect(Open3).to(have_received(:capture2e).with(*shard("minitest", 2, 3), chdir: "/app"))
  end

  def baselines(serial, **jobs)
    command = described_class.new("rspec", ["t.rb"], root: "/app", **jobs)
    allow(command).to(receive_messages(baseline: serial, parallel: ["✓", "split"]))
    command.baselines
  end

  it "runs the suite split across processes only with several workers, once it is green in one", :aggregate_failures do
    green = ["✓", "Baseline: configured test suite is green"]
    expect(baselines(green, jobs: 2)).to(eq([green, ["✓", "split"]]))
    expect(baselines(green, jobs: 1)).to(eq([green]))
    expect(baselines(green)).to(eq([green]))
    expect(baselines(["✗", "red"], jobs: 2)).to(eq([["✗", "red"]]))
  end

  # thor, green in one process, red on four workers that share spec/sandbox.
  it "warns with every worker's failing tests when the suite is red split across processes", :aggregate_failures do
    red = ["rspec ./spec/a_spec.rb:3 # A\n", "", "rspec ./spec/b_spec.rb:9 # B\nrspec ./spec/a_spec.rb:3 # A\n"]
    status, text = parallel("rspec", red)
    expect(status).to(eq("!"))
    expect(text).to(
      eq(
        "Parallel baseline: #{format(described_class::SHARED, 3, 3)}\n  " \
          "failing tests:\n    ./spec/a_spec.rb:3\n    ./spec/b_spec.rb:9"
      )
    )
    expect(text).to(start_with("Parallel baseline: red split across 3 processes (jobs: 3), green in one: "))
  end
end
