# frozen_string_literal: true

require "fileutils"
require "kimera/frameworks/minitest_adapter"
require "kimera/frameworks/rspec_adapter"
require "kimera/support/test_exit"
require "stringio"
require "tmpdir"

# A test that calls exit or abort fails; the SystemExit no longer unwinds the
# worker, the isolated child or kimera itself.
RSpec.describe(Kimera::TestExit) do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def raised(status, message, frames)
    SystemExit.new(status, message).tap { |error| error.set_backtrace(frames) }
  end

  describe ".failure" do
    let(:frames) { ["#{Dir.pwd}/app/task.rb:3:in 'Kernel#exit'", "#{Dir.pwd}/app/task.rb:3:in 'Task#run'"] }

    it "keeps the status and the frames, and names where exit was called", :aggregate_failures do
      failure = described_class.failure(raised(3, "exit", frames))
      expect(failure).to(be_a(SystemExit))
      expect(failure.status).to(eq(3))
      expect(failure.message).to(eq("exit(3) called from app/task.rb:3:in 'Kernel#exit'"))
      expect(failure.backtrace).to(eq(frames))
    end

    it "keeps abort's message" do
      failure = described_class.failure(raised(1, "no such task", ["/elsewhere/task.rb:9:in 'Kernel#abort'"]))
      expect(failure.message).to(eq("exit(1) called from /elsewhere/task.rb:9:in 'Kernel#abort': no such task"))
    end
  end

  describe "under RSpec" do
    around do |example|
      groups = RSpec.world.example_groups.dup
      streams = %i[output_stream error_stream deprecation_stream].map { |name| RSpec.configuration.public_send(name) }
      example.run
    ensure
      (RSpec.world.example_groups - groups).each { |group| RSpec.world.example_groups.delete(group) }
      config = RSpec.configuration
      config.output_stream, config.error_stream, config.deprecation_stream = streams
      $probe = nil
    end

    def fixture
      File.join(dir, "exits_spec.rb").tap do |path|
        File.write(path, <<~RUBY)
          RSpec.describe "KimeraExits" do
            after { $probe << :after }

            it("exits") { exit(4) }

            it("passes") { expect(1).to eq(1) }

            it("is interrupted") { raise Interrupt }
          end
        RUBY
      end
    end

    # Hides RSpec's warning about re-pointing already-initialized streams.
    def adapter
      original = $stderr
      $stderr = StringIO.new
      Kimera::Frameworks::RSpecAdapter.build.source([fixture])
    ensure
      $stderr = original
    end

    def run(loaded, name)
      $probe = []
      id = loaded.test_ids.find { |test| loaded.describe(test) == "KimeraExits #{name}" }
      [id, loaded.run([id])]
    rescue SystemExit => error
      [id, error]
    end

    it "fails the example that exits, after its after hooks ran", :aggregate_failures do
      id, outcome = run(adapter, "exits")
      expect(outcome).to(be_a(Kimera::Frameworks::RunOutcome))
      expect(outcome.failed_ids).to(eq([id]))
      lines = outcome.failures[id].lines(chomp: true)
      expect(lines.first).to(eq("SystemExit: exit(4) called from #{dir}/exits_spec.rb:4:in 'Kernel#exit'"))
      expect(lines[1]).to(match(/\A    \S*exits_spec\.rb:4:in /))
      expect($probe).to(eq([:after]))
    end

    it "runs the next example normally" do
      loaded = adapter
      run(loaded, "exits")
      expect(run(loaded, "passes").last.passed?).to(be(true))
    end

    it "lets an interrupt through" do
      loaded = adapter
      expect { run(loaded, "is interrupted") }.to(raise_error(Interrupt))
    end
  end

  describe "under Minitest" do
    after { $probe = nil }

    def fixture
      File.join(dir, "exits_test.rb").tap do |path|
        File.write(path, <<~RUBY)
          require "minitest"
          class KimeraExitsTest < Minitest::Test
            def teardown = $probe&.push(:teardown)
            def test_aborts = abort("no such task")
            def test_interrupted = raise(Interrupt)
          end
        RUBY
      end
    end

    # abort prints its message to $stderr.
    def run(id)
      $probe = []
      original = $stderr
      $stderr = StringIO.new
      Kimera::Frameworks::MinitestAdapter.build.source([fixture]).run([id])
    rescue SystemExit => error
      error
    ensure
      $stderr = original
    end

    it "fails the test that aborts, after its teardown ran", :aggregate_failures do
      id = "KimeraExitsTest#test_aborts"
      outcome = run(id)
      expect(outcome).to(be_a(Kimera::Frameworks::RunOutcome))
      expect(outcome.failed_ids).to(eq([id]))
      expect(outcome.failures[id].lines(chomp: true).first(2)).to(
        eq(
          [
            "UnexpectedError: SystemExit: exit(1) called from #{dir}/exits_test.rb:4:in 'Kernel#abort': no such task",
            "    #{dir}/exits_test.rb:4:in 'Kernel#abort'"
          ]
        )
      )
      expect($probe).to(eq([:teardown]))
    end

    it "lets an interrupt through" do
      expect { run("KimeraExitsTest#test_interrupted") }.to(raise_error(Interrupt))
    end
  end
end
