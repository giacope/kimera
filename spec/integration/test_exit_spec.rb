# frozen_string_literal: true

# A mutant that makes code under test call abort fails the test that runs it,
# so the mutant is killed. The SystemExit used to unwind the warm worker (or
# the isolated child), and the mutant was scored harness_error.
RSpec.describe("abort in code under test (end-to-end)") do
  def test_fixture(root)
    FileUtils.mkdir_p(%w[app spec test].map { |dir| File.join(root, dir) })
    File.write(File.join(root, "app", "task.rb"), <<~RUBY)
      class Task
        def run(ready)
          abort("not ready") unless ready
          :done
        end
      end
    RUBY
    File.write(File.join(root, "spec", "task_spec.rb"), <<~RUBY)
      require_relative "../app/task"
      RSpec.describe(Task) { it("runs") { expect(Task.new.run(true)).to(eq(:done)) } }
    RUBY
    File.write(File.join(root, "test", "task_test.rb"), <<~RUBY)
      require "minitest"
      require_relative "../app/task"
      class TaskTest < Minitest::Test
        def test_runs = assert_equal(:done, Task.new.run(true))
      end
    RUBY
  end

  # The killed mutant's detail, and how many mutants couldn't be judged.
  def test_killer(args, tests: "spec/**/*_spec.rb")
    Dir.mktmpdir("kimera-abort") do |root|
      test_fixture(root)
      test_run(cwd: root, tests: tests, args: args) do |output, report, _status|
        raise(ArgumentError, "no JSON report; output:\n#{output}") unless report

        killed = report["results"].find { |result| result["status"] == "killed" }
        { errors: report["counts"]["error"], killed: !killed.nil?, detail: killed&.fetch("detail") }
      end
    end
  end

  let(:detail) { a_string_including("SystemExit: exit(1) called from app/task.rb", ": not ready") }

  it "kills the mutant in a serial warm run (RSpec)" do
    expect(test_killer(["--jobs", "1"])).to(match(errors: 0, killed: true, detail: detail))
  end

  it "kills the mutant with parallel warm workers (RSpec)" do
    expect(test_killer(["--jobs", "2"])).to(match(errors: 0, killed: true, detail: detail))
  end

  it "kills the mutant in an isolated child (RSpec)" do
    expect(test_killer(["--isolated"])).to(include(errors: 0, killed: true))
  end

  it "kills the mutant in a warm run and an isolated child (Minitest)", :aggregate_failures do
    tests = "test/**/*_test.rb"
    expect(test_killer(["--framework", "minitest"], tests: tests)).to(match(errors: 0, killed: true, detail: detail))
    expect(test_killer(["--framework", "minitest", "--isolated"], tests: tests)).to(include(errors: 0, killed: true))
  end

  def test_red(root, args)
    test_fixture(root)
    File.write(File.join(root, "spec", "task_spec.rb"), <<~RUBY)
      require_relative "../app/task"
      RSpec.describe(Task) { it("runs unready") { Task.new.run(false) } }
    RUBY
    test_run(cwd: root, args: args) { |output, _report, status| yield(output, status) }
  end

  it "reports a test that aborts as a failing baseline test, serially and in parallel", :aggregate_failures do
    [["--jobs", "1"], ["--jobs", "2"]].each do |args|
      Dir.mktmpdir("kimera-abort") do |root|
        test_red(root, args) do |output, status|
          expect(output).to(include("not green: ./spec/task_spec.rb[1:1]", "SystemExit: exit(1) called from app/"))
          expect(status).to(eq(1))
        end
      end
    end
  end
end
