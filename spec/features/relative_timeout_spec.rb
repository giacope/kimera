# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Deleting `pool.shutdown` fails no test, but every test's setup then waits
# out wait_for_termination. The coverage pass timed each test, so the first
# covering test run (the fastest in the baseline) past baseline × factor +
# slack settles the mutant.
RSpec.describe("kimera run's relative time budget (end-to-end)", :aggregate_failures) do
  def test_pusher(root)
    FileUtils.mkdir_p([File.join(root, "app"), File.join(root, "spec", "support")])
    File.write(File.join(root, "spec", "support", "pool.rb"), <<~RUBY)
      class Pool
        def initialize = @done = Queue.new

        def shutdown = @done << true

        def wait_for_termination(seconds) = !@done.pop(timeout: seconds).nil?
      end
    RUBY
    File.write(File.join(root, "app", "pusher.rb"), <<~RUBY)
      module Pusher
        def self.stop(pool)
          pool.shutdown
          pool.wait_for_termination(0.5)
        end
      end
    RUBY
    File.write(File.join(root, "spec", "pusher_spec.rb"), <<~RUBY)
      require_relative "../app/pusher"
      require_relative "support/pool"

      RSpec.describe Pusher do
        before { described_class.stop(Pool.new) }

        4.times { |i| it("sends push \#{i}") { expect(i + 1).to be > i } }
      end
    RUBY
  end

  def test_slowed(arguments)
    Dir.mktmpdir("kimera-budget") do |root|
      test_pusher(root)
      test_outcome(cwd: root, arguments: ["--no-progress", *arguments])
    end
  end

  def test_deletion(run) = run.results.first.to_h

  it "reports the mutant that slows every test as a timeout, naming the budget" do
    run = test_slowed(["--timeout-slack", "0.2"])
    expect(test_deletion(run)).to(include("status" => "timeout", "duration" => be < 1.5), run.output)
    expect(test_deletion(run)["detail"]).to(
      match(/\A\S+pusher_spec\.rb\[1:[1-4]\] ran past its relative time budget with the mutant on /)
        .and(include("× 10.0 + 0.2s), and in "))
    )
  end

  it "lets it run every covering test and survive under --no-relative-timeout" do
    run = test_slowed(["--no-relative-timeout"])
    expect(test_deletion(run)).to(include("status" => "survived", "duration" => be >= 2.0), run.output)
  end
end
