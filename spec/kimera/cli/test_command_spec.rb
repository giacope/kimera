# frozen_string_literal: true

require "kimera/cli"
require "kimera/cli/test_command"
require "tmpdir"
require "fileutils"
require "stringio"

RSpec.describe(Kimera::CLI::TestCommand) do
  def watched = 125

  def status(success, signal = nil)
    instance_double(Process::Status, success?: success, termsig: signal)
  end

  def loading(framework, output: "", success: true)
    command = described_class.new(framework, ["t.rb"], root: "/app")
    allow(Kimera::Execution::SUITE).to(receive(:call).and_return([output, status(success)]))
    command.loading
  end

  it "loads minitest files without running them" do
    loading("minitest")
    command = ["bundle", "exec", "ruby", "-e", described_class::DRY_RUN, "t.rb"]
    expect(Kimera::Execution::SUITE).to(
      have_received(:call).with(
        { "KIMERA" => "1" }, *command, chdir: "/app",
        limit: watched
      )
    )
  end

  # The load path run uses: each file's nearest test/ or spec/, the
  # project's own, and load_path: from the configuration.
  # Doctor's load check of a nested test file, with a configured load path; the file.
  def loaded_in(root)
    FileUtils.mkdir_p([File.join(root, "test"), File.join(root, "lib", "x", "test")])
    allow(Kimera::Execution::SUITE).to(receive(:call).and_return(["", status(true)]))
    stub_const("ENV", ENV.to_h.merge("KIMERA_LOAD_PATH" => "support"))
    File.join(root, "lib", "x", "test", "a_test.rb").tap do |file|
      described_class.new("minitest", [file], root: root).loading
    end
  end

  it "puts the same folders on doctor's load path as kimera run does" do
    Dir.mktmpdir do |root|
      file = loaded_in(root)
      command = [
        "bundle", "exec", "ruby", "-I", "support", "-I", "lib/x/test", "-I", "test",
        "-e", described_class::DRY_RUN, file
      ]
      expect(Kimera::Execution::SUITE)
        .to(have_received(:call).with({ "KIMERA" => "1" }, *command, chdir: root, limit: watched))
    end
  end

  it "loads rspec files with --dry-run" do
    loading("rspec")
    expect(Kimera::Execution::SUITE).to(
      have_received(:call).with(
        { "KIMERA" => "1" }, "bundle", "exec", "rspec", "--dry-run", "t.rb", chdir: "/app",
        limit: watched
      )
    )
  end

  # A helper gating its coverage floor on KIMERA must not fail the dry run,
  # which executes no code at all.
  it "runs the full baseline with KIMERA set too" do
    command = described_class.new("rspec", ["t.rb"], root: "/app")
    allow(Kimera::Execution::SUITE).to(receive(:call).and_return(["", status(true)]))
    command.baseline
    expect(Kimera::Execution::SUITE).to(
      have_received(:call).with(
        { "KIMERA" => "1" }, "bundle", "exec", "rspec", "t.rb",
        chdir: "/app", limit: watched
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

  # R4-KR6: maintenance_tasks' dummy app aborts with Rails' pending-migrations message.
  it "quotes the first lines of a suite that aborts with a plain message", :aggregate_failures do
    said = "\nMigrations are pending. To resolve this issue, run:\n\n        bin/rails db:migrate\n\n" \
      "You have 9 pending migrations:\n\n20201211151756_create_runs.rb\n"
    expect(loading("minitest", output: said, success: false)).to(
      eq(
        [
          "✗", "Test loading: test command failed: Migrations are pending. To resolve this issue, run: " \
            "bin/rails db:migrate You have 9 pending migrations:"
        ]
      )
    )
    expect(loading("minitest", output: "\n  \n", success: false)).to(eq(["✗", "Test loading: test command failed"]))
  end

  it "warns without failing when Bundler is missing" do
    command = described_class.new("rspec", [], root: "/app")
    allow(Kimera::Execution::SUITE).to(receive(:call).and_raise(Errno::ENOENT))
    expect(command.loading).to(eq(["!", "Test loading: Bundler is unavailable; not checked"]))
  end

  # R6B3-M1: doctor runs the baseline as the Rakefile's test task does, and
  # says so when a red suite is green with warnings the other way.
  def warned(rakefile, outcomes)
    Dir.mktmpdir do |root|
      File.write(File.join(root, "Rakefile"), rakefile)
      calls = []
      allow(Kimera::Execution::SUITE).to(receive(:call)) { |_env, *command, **| (calls << command) && outcomes.shift }
      [described_class.new("minitest", ["t.rb"], root: root).baseline, calls.map { it[3] }]
    end
  end

  it "runs a minitest baseline with ruby -w when the Rakefile's test task does" do
    result, flags = warned("Rake::TestTask.new\n", [["1 runs, 0 failures", status(true)]])
    expect([result, flags]).to(eq([["✓", "Baseline: configured test suite is green"], ["-w"]]))
  end

  def red = ["1 runs, 1 failures", status(false)]

  it "names warnings as the difference when a red baseline is green the other way", :aggregate_failures do
    quiet = warned("Rake::TestTask.new { |t| t.warning = false }\n", [red, ["", status(true)]])
    expect([quiet.first.last, quiet.last]).to(match([include(Kimera::Frameworks::TestTask::UNWARNED), ["-e", "-w"]]))
    loud = warned("Rake::TestTask.new\n", [red, ["", status(true)]])
    expect([loud.first.last, loud.last]).to(match([include(Kimera::Frameworks::TestTask::WARNED), ["-w", "-e"]]))
  end

  def split(framework)
    Dir.mktmpdir do |root|
      File.write(File.join(root, "Rakefile"), "Rake::TestTask.new\n")
      calls = []
      allow(Kimera::Execution::SUITE).to(receive(:call)) { |_env, *command, **| (calls << command) && ["", status(true)] }
      described_class.new(framework, ["t.rb"], root: root).baselines(2)
      calls.map { it[3] }
    end
  end

  it "splits an RSpec baseline without the -w a Rakefile's test task would give Minitest" do
    expect([split("rspec").include?("-w"), split("minitest").uniq]).to(eq([false, ["-w"]]))
  end

  it "says nothing of warnings when the suite is red either way" do
    expect(warned("Rake::TestTask.new\n", [red, red]).first.last).not_to(include("ruby -w"))
  end

  def baseline(framework, output, signal = nil)
    command = described_class.new(framework, ["t.rb"], root: "/app")
    allow(Kimera::Execution::SUITE).to(receive(:call).and_return([output, status(false, signal)]))
    command.baseline.last
  end

  # R5-KR4: rubytoolbox under the OOM killer; doctor headlined an example's name that held "error".
  it "says first that the suite was killed by a signal, never naming a passing example", :aggregate_failures do
    output = "Catalog import\n  raises an error when fetching fails\n"
    expect(
      baseline(
        "rspec", output,
        9
      )
    ).to(start_with("Baseline: the suite was killed by SIGKILL before it printed a summary — out of memory?"))
    expect(
      baseline(
        "rspec", output,
        11
      )
    ).to(start_with("Baseline: the suite was killed by SIGSEGV before it printed a summary ("))
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
    allow(Kimera::Execution::SUITE).to(receive(:call).and_raise(Errno::ENOENT))
    expect(command.baseline).to(eq(["✗", "Baseline: Bundler is unavailable; run your test suite, then retry"]))
  end

  # Each shard's command answers with its own output; an empty one passes.
  def answering(framework, outputs)
    shards = outputs.each_index.map { |index| Kimera::CLI::TestShard.new(index, outputs.size).argv(framework) }
    allow(Kimera::Execution::SUITE).to(receive(:call)) do |_env, *argv, **|
      output = outputs[shards.index { |shard| argv.each_cons(shard.size).include?(shard) }]
      [output, status(output.empty?)]
    end
  end

  def parallel(framework, outputs)
    answering(framework, outputs)
    described_class.new(framework, ["t.rb"], root: "/app").parallel(outputs.size)
  end

  def shard(framework, index, count)
    [{ "KIMERA" => "1" }, "bundle", "exec", "ruby", *Kimera::CLI::TestShard.new(index, count).argv(framework), "t.rb"]
  end

  it "runs one process per worker, each on its share of the tests", :aggregate_failures do
    expect(parallel("rspec", ["", ""])).to(
      eq(["✓", "Parallel baseline: green split across 2 processes too (jobs: 2; #{described_class::SAMPLE})"])
    )
    [0, 1].each { |index| expect(Kimera::Execution::SUITE).to(have_received(:call).with(*shard("rspec", index, 2), chdir: "/app", limit: watched)) }
    parallel("minitest", ["", "", ""])
    expect(Kimera::Execution::SUITE).to(
      have_received(:call).with(
        *shard("minitest", 2, 3), chdir: "/app",
        limit: watched
      )
    )
  end

  def baselines(serial, jobs: nil)
    command = described_class.new("rspec", ["t.rb"], root: "/app")
    allow(command).to(receive_messages(baseline: serial, parallel: ["✓", "split"]))
    jobs ? command.baselines(jobs) : command.baselines
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

  # R4-KR4: stringer's SimpleCov minimum_coverage(100) fails each half of the suite.
  it "tells a coverage floor apart from shared state", :aggregate_failures do
    floor = "Parallel baseline: #{format(described_class::FLOOR, 2, 2)}"
    expect(parallel("rspec", ["10 examples, 0 failures\n", "12 examples, 0 failures\n"])).to(eq(["!", floor]))
    expect(parallel("rspec", ["10 examples, 0 failures\n", ""]).last).to(eq(floor))
    expect(floor).to(start_with("Parallel baseline: split across 2 processes (jobs: 2), each part exits non-zero"))
  end

  it "blames shared state when any red part has a failing test" do
    mixed = ["10 examples, 0 failures\n", "rspec ./spec/b_spec.rb:9 # B\n3 examples, 1 failure\n"]
    expect(parallel("rspec", mixed).last).to(start_with("Parallel baseline: #{format(described_class::SHARED, 2, 2)}"))
  end

  # K3-2: a suite that never exits hung doctor for 25 minutes, silently.
  describe "a suite that never exits" do
    def hung
      Dir.mktmpdir do |root|
        return Kimera::Execution::SuiteCapture.new(StringIO.new).call({}, "sleep", "30", chdir: root, limit: 0.6)
      end
    end

    it "is stopped at its limit, and says how long it waited", :aggregate_failures do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      output, status = hung
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to(be < 5)
      expect(status.success?).to(be(false))
      expect(output).to(include("the suite did not exit within 0.6 s"))
    end

    it "fails doctor's baseline with the reason" do
      command = described_class.new("rspec", ["t.rb"], root: "/app")
      overdue = Kimera::Execution::SuiteCapture::Overdue.new(125)
      note = format(Kimera::Execution::SuiteCapture::OVERDUE, 125)
      allow(Kimera::Execution::SUITE).to(receive(:call).and_return(["1 example\n#{note}\n", overdue]))
      expect(command.baseline.last).to(include("the suite did not exit within 125 s"))
    end

    it "allows two minutes and five seconds a test file" do
      allow(Kimera::Execution::SUITE).to(receive(:call).and_return(["", status(true)]))
      described_class.new("rspec", %w[a.rb b.rb], root: "/app").baseline
      expect(Kimera::Execution::SUITE).to(have_received(:call).with(any_args, chdir: "/app", limit: 130))
    end

    it "says the suite is still running every half minute" do
      said = StringIO.new
      Kimera::Execution::SuiteCapture.new(said).__send__(:tick, 30.1)
      expect(said.string).to(eq("kimera: the suite is still running (30 s)…\n"))
    end
  end

  it "finishes a quick suite under a watch without ticking" do
    Dir.mktmpdir do |root|
      said = StringIO.new
      output, status = Kimera::Execution::SuiteCapture.new(said).call({}, "echo", "done", chdir: root, limit: 10)
      expect([output, status.success?, said.string]).to(eq(["done\n", true, ""]))
    end
  end

  # R6B4-M8: `kimera run` leaves out the tests exclude_test_names names;
  # doctor's baseline ran them, and called the suite red on one it leaves out.
  describe "the tests exclude_test_names leaves out" do
    def suite(root, framework)
      spec = framework == "rspec"
      File.join(root, spec ? "gauge_spec.rb" : "gauge_test.rb").tap do |file|
        File.write(file, spec ? rspec_suite : minitest_suite)
      end
    end

    def rspec_suite
      <<~RUBY
        RSpec.describe("Gauge") do
          it("reads") { expect(1).to(eq(1)) }
          it("needs a network") { raise("offline") }
        end
      RUBY
    end

    def minitest_suite
      <<~RUBY
        require "minitest/autorun"
        class GaugeTest < Minitest::Test
          def test_reads = assert(true)
          def test_needs_a_network = raise("offline")
        end
      RUBY
    end

    def baseline(framework, names)
      Dir.mktmpdir do |root|
        described_class.new(framework, [suite(root, framework)], root: root, names: names).baselines(2).map(&:first)
      end
    end

    it "leaves them out of the baseline, serial and split, as run does", :aggregate_failures do
      expect(baseline("rspec", ["needs a network"])).to(eq(%w[✓ ✓]))
      expect(baseline("minitest", ["GaugeTest#test_needs_a_network"])).to(eq(%w[✓ ✓]))
      expect(baseline("rspec", ["gauge_spec.rb\\[1:2\\]"])).to(eq(%w[✓ ✓]))
      expect(baseline("rspec", [])).to(eq(["✗"]))
    end
  end
end
