# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "kimera/execution/isolated_child_command"
require "kimera/frameworks/seed"

# A mutant's child stops at its first failing test: any failure kills it. The
# baseline's child runs them all, so a red baseline names every failing test.
RSpec.describe(Kimera::Execution::IsolatedPlan::ChildCommand) do
  let(:two) { "RSpec.describe('two') { 2.times { |n| it(n.to_s) { expect(n).to(eq(-1)) } } }\n" }

  # The first example runs a failing group of its own on the shared reporter,
  # as a spec of an RSpec extension does; only the second fails itself.
  let(:nested) do
    <<~RUBY
      RSpec.describe("outer") do
        it("runs an inner suite") { RSpec::Core::ExampleGroup.describe { it { fail } }.run(RSpec.configuration.reporter) }
        it("fails") { fail }
      end
    RUBY
  end

  def failing(source, first_failure)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "a_spec.rb"), source)
      ledger = File.join(dir, "ledger.json")
      File.write("#{ledger}.request", JSON.generate("tests" => ["./a_spec.rb"], "first_failure" => first_failure))
      env = { "BUNDLE_GEMFILE" => File.expand_path("../../../../Gemfile", __dir__) }
      child = [RbConfig.ruby, "-rbundler/setup", described_class::CHILD, ledger, "#{ledger}.request"]
      Open3.capture2e(env, *child, chdir: dir)
      JSON.parse(File.read(ledger)).values_at("failures", "failing")
    end
  end

  it "has the RSpec child stop at the first failing test when asked", :aggregate_failures do
    expect(failing(two, true)).to(eq([1, ["./a_spec.rb[1:1]"]]))
    expect(failing(two, false)).to(eq([2, ["./a_spec.rb[1:1]", "./a_spec.rb[1:2]"]]))
  end

  def drawn(test) = Random.new(Kimera::Seed.new("KIMERA_SEED" => "31").for(test)).rand(1_000_000)

  def seeded(child, file, source, request, seed: 31)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, file), source)
      ledger = File.join(dir, "ledger.json")
      File.write("#{ledger}.request", JSON.generate(request.merge("seed" => seed)))
      env = { "BUNDLE_GEMFILE" => File.expand_path("../../../../Gemfile", __dir__) }
      Open3.capture2e(env, RbConfig.ruby, "-rbundler/setup", child, ledger, "#{ledger}.request", chdir: dir)
      JSON.parse(File.read(ledger)).fetch("failures")
    end
  end

  # The warm path seeds each test the same way, so a test draws the same numbers in either tier.
  it "seeds each RSpec test from the run's seed and the test's id", :aggregate_failures do
    source = "RSpec.describe('r') { it('draws') { expect(rand(1_000_000)).to(eq(#{drawn("./a_spec.rb[1:1]")})) } }\n"
    expect(seeded(described_class::CHILD, "a_spec.rb", source, { "tests" => ["./a_spec.rb"] })).to(eq(0))
    expect(seeded(described_class::CHILD, "a_spec.rb", source, { "tests" => ["./a_spec.rb"] }, seed: 32)).to(eq(1))
  end

  it "seeds each Minitest test from the run's seed and the test's id, and orders by the seed", :aggregate_failures do
    source = <<~RUBY
      require "minitest"
      class DrawTest < Minitest::Test
        def test_draws = assert_equal(#{drawn("DrawTest#test_draws")}, rand(1_000_000))
        def test_seed = assert_equal(31, Minitest.seed)
      end
    RUBY
    request = { "tests" => %w[DrawTest#test_draws DrawTest#test_seed], "files" => ["draw_test.rb"] }
    expect(seeded(described_class::MINITEST_CHILD, "draw_test.rb", source, request)).to(eq(0))
    expect(seeded(described_class::MINITEST_CHILD, "draw_test.rb", source, request, seed: 32)).to(eq(1))
  end

  it "has the Minitest child run every test and name each failure unless asked to stop at the first",
    :aggregate_failures do
    source = "require 'minitest'\nclass TwoTest < Minitest::Test\n  def test_a = flunk\n  def test_b = flunk\nend\n"
    request = { "tests" => %w[TwoTest#test_a TwoTest#test_b], "files" => ["two_test.rb"] }
    ran = ->(first) { minitest_ledger(source, request.merge("first_failure" => first)) }
    expect(ran.call(false)).to(eq([2, %w[TwoTest#test_a TwoTest#test_b]]))
    expect([ran.call(true), ran.call(nil)]).to(eq([[1, ["TwoTest#test_a"]]] * 2))
  end

  def minitest_ledger(source, request)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, "two_test.rb"), source)
      ledger = File.join(dir, "ledger.json")
      File.write("#{ledger}.request", JSON.generate(request))
      env = { "BUNDLE_GEMFILE" => File.expand_path("../../../../Gemfile", __dir__) }
      Open3.capture2e(
        env, RbConfig.ruby, "-rbundler/setup", described_class::MINITEST_CHILD, ledger,
        "#{ledger}.request", chdir: dir
      )
      JSON.parse(File.read(ledger)).values_at("failures", "failing")
    end
  end

  it "asks the child for the run's seed only when there is one", :aggregate_failures do
    expect(described_class.new(framework: "rspec", test_files: [], seed: 4).request(["t"])).to(include("seed" => 4))
    expect(described_class.new(framework: "rspec", test_files: []).request(["t"])).not_to(have_key("seed"))
  end

  # R6B3-M1: a mirror runs the suite with the ruby flags the run gives, as the
  # warm pass runs it: `-w` when the Rakefile's test task warns.
  def ruby(**)
    child = described_class.new(framework: "minitest", test_files: [])
    Dir.mktmpdir { |dir| child.command(dir, child.request(["t"], **), ledger: File.join(dir, "l"), paths: []).last }
  end

  it "runs the child ruby with the warnings the run asks for, and none otherwise", :aggregate_failures do
    expect(ruby(warnings: ["-w"]).first(2)).to(eq(["ruby", "-w"]))
    expect(ruby.first(2)).to(eq(["ruby", described_class::MINITEST_CHILD]))
  end

  it "stops only for a failure of a test it was asked to run" do
    expect(failing(nested, true).last).to(include("./a_spec.rb[1:2]"))
  end
end
