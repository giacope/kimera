# frozen_string_literal: true

require "fileutils"
require "tmpdir"

# Deleting `pool.shutdown` fails no test, but every test's setup then waits
# out wait_for_termination. The coverage pass timed each test, so the first
# covering test past baseline × factor + slack settles the mutant.
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

  def test_slowed(args, &)
    Dir.mktmpdir("kimera-budget") do |root|
      test_pusher(root)
      test_run(cwd: root, args: ["--no-progress", *args], &)
    end
  end

  def test_deletion(report) = report["results"].first

  it "reports the mutant that slows every test as a timeout, naming the budget" do
    test_slowed(["--timeout-slack", "0.2"]) do |output, report, _status|
      expect(report).not_to(be_nil, "no JSON report; output:\n#{output}")
      row = test_deletion(report)
      expect(row["status"]).to(eq("timeout"))
      expect(row["detail"]).to(match(/\A\S+pusher_spec\.rb\[1:1\] ran past its relative time budget with the mutant on /))
      expect(row["detail"]).to(include("× 10.0 + 0.2s), and in "))
      expect(row["duration"]).to(be < 1.5)
    end
  end

  it "lets it run every covering test and survive under --no-relative-timeout" do
    test_slowed(["--no-relative-timeout"]) do |_output, report, _status|
      row = test_deletion(report)
      expect(row["status"]).to(eq("survived"))
      expect(row["duration"]).to(be >= 2.0)
    end
  end
end
