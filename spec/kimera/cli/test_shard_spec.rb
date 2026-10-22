# frozen_string_literal: true

require "kimera/cli"
require "kimera/cli/test_shard"
require "open3"
require "tmpdir"

RSpec.describe(Kimera::CLI::TestShard) do
  let(:rails_suite) do
    <<~RUBY
      require "minitest/autorun"
      module ActiveSupport
        singleton_class.attr_accessor(:parallelize_test_databases)
        self.parallelize_test_databases = true
        module Testing
          module Parallelization
            def self.before_fork_hooks = []
            def self.after_fork_hooks = [->(index) { File.write("database_\#{index}", ENV.fetch("PARALLEL_WORKERS")) }]
          end
        end
        class TestCase < Minitest::Test
          singleton_class.attr_accessor(:parallel_worker_id)
        end
      end
      module ActiveRecord
        class Base; end
      end
      $LOADED_FEATURES << "active_record/test_databases.rb"
      class ShardTest < ActiveSupport::TestCase
        def test_worker = assert_equal("1", File.read("database_\#{ActiveSupport::TestCase.parallel_worker_id}"))
      end
    RUBY
  end

  it "gives each RSpec process its index among the count, in its script", :aggregate_failures do
    rspec = described_class.new(1, 4).argv("rspec")
    expect(rspec.first).to(eq("-e"))
    expect(rspec.last).to(include("count, index = 4, 1", "% count != index", "RSpec::Core::Runner.run(ARGV)"))
    expect(described_class.new(1, 4).argv("rspec", ["-I", "test"]).first).to(eq("-e"))
  end

  it "gives each Minitest process its index among the count, in its script", :aggregate_failures do
    minitest = described_class.new(2, 3).argv(:minitest, ["-I", "test"])
    expect(minitest.first(3)).to(eq(["-I", "test", "-e"]))
    expect(described_class.new(2, 3).argv(:minitest).first).to(eq("-e"))
    expect(minitest.last).to(include("count, index = 3, 2", "% count == index", "ARGV.clear"))
  end

  def test_shards(framework, source)
    Dir.mktmpdir("kimera-shard") do |dir|
      File.write(File.join(dir, "shard_test.rb"), source)
      [0, 1].map do |index|
        command = ["ruby", *described_class.new(index, 2).argv(framework), "shard_test.rb"]
        output, status = Open3.capture2e(*command, chdir: dir)
        [output[/^(\d+) (?:examples|runs),/, 1].to_i, status.success?]
      end
    end
  end

  # Kimera's own specs load and run spec files inside an example: those
  # examples are the test's, not the suite's, and none may be dealt out.
  it "deals out the loaded RSpec examples in turn, and none defined while they run" do
    source = <<~RUBY
      RSpec.describe("outer") do
        3.times { |i| it("keeps \#{i}") { expect(i).to(be < 3) } }
        it("defines its own") { expect(RSpec.describe("inner") { 4.times { |i| it("\#{i}") {} } }.descendant_filtered_examples.size).to(eq(4)) }
      end
    RUBY
    # The second process runs the inner group's four too, where it was defined.
    expect(test_shards("rspec", source)).to(eq([[2, true], [6, true]]))
  end

  it "deals out each loaded Minitest class's tests in turn, and none of a class defined later" do
    source = <<~RUBY
      require "minitest/autorun"
      class ShardTest < Minitest::Test
        3.times { |i| define_method("test_keeps_\#{i}") { assert(i < 3) } }
        def test_defines_its_own = assert_equal(4, Class.new(Minitest::Test) { 4.times { |i| define_method("test_\#{i}") {} } }.runnable_methods.size)
      end
    RUBY
    expect(test_shards("minitest", source)).to(eq([[2, true], [2, true]]))
  end

  # Run at once, two shards of a Rails suite each forked Rails' own workers,
  # and those shared test.sqlite3_0 and the rest: "database is locked".
  # Each of two shards' exit status, the suite written to dir.
  def sharded(dir)
    File.write(File.join(dir, "shard_test.rb"), rails_suite)
    [0, 1].map do |index|
      Open3.capture2e("ruby", *described_class.new(index, 2).argv(:minitest), "shard_test.rb", chdir: dir).last
    end
  end

  it "gives each shard of a Rails suite its own test database, and runs it in one process", :aggregate_failures do
    Dir.mktmpdir("kimera-shard") do |dir|
      expect(sharded(dir)).to(all(be_success))
      expect(Dir.children(dir).grep(/^database_/).sort).to(eq(%w[database_0 database_1]))
      expect(File.read(File.join(dir, "database_1"))).to(eq("1"))
    end
  end
end
