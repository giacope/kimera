# frozen_string_literal: true

require "kimera/cli"
require "kimera/cli/test_shard"
require "open3"
require "tmpdir"

RSpec.describe(Kimera::CLI::TestShard) do
  it "gives each process its index among the count, in the framework's script", :aggregate_failures do
    rspec = described_class.argv("rspec", 1, 4)
    expect(rspec.first).to(eq("-e"))
    expect(rspec.last).to(include("(position += 1) % 4 != 1", "RSpec::Core::Runner.run(ARGV)"))
    minitest = described_class.argv(:minitest, 2, 3)
    expect(minitest.first(2)).to(eq(["-Itest", "-e"]))
    expect(minitest.last).to(include("(offset + position) % 3 == 2", "ARGV.clear"))
  end

  def test_shards(framework, source)
    Dir.mktmpdir("kimera-shard") do |dir|
      File.write(File.join(dir, "shard_test.rb"), source)
      [0, 1].map do |index|
        command = ["ruby", *described_class.argv(framework, index, 2), "shard_test.rb"]
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
end
