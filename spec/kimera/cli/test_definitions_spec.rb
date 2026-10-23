# frozen_string_literal: true

require "fileutils"
require "kimera/cli/test_definitions"
require "tmpdir"

# R4-KL3: zeitwerk's test/**/*_test.rb matched one support class and none of
# its 50 tests, and doctor passed it.
RSpec.describe(Kimera::CLI::TestDefinitions) do
  let(:dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(dir) }

  def files(**texts)
    texts.map do |name, text|
      File.join(dir, name.to_s).tap { |path| File.write(path, text) }
    end
  end

  def count(text) = described_class.new(files(a: text)).count

  it "counts a Minitest test, an Active Support test and a spec example", :aggregate_failures do
    tests = [
      "  def test_sum\n", "  test \"sums\" do\n", "  test(\"sums\") { }\n", "  it \"sums\" do\n", "it { }\n",
      "specify { }\n", "  example \"x\" do\n", "  scenario \"x\" do\n", "  it_behaves_like \"a sum\"\n",
      "  it_should_behave_like \"a sum\"\n", "  include_examples \"a sum\"\n", "RSpec.describe(A) { it { } }\n",
      "class ATest < Minitest::Test; def test_a; end; end\n",
      "    define_method(\"test_keeps_\#{i}\") do\n", "  define_method :test_a do\n"
    ]
    expect(tests.map { |text| count(text) }).to(all(eq(1)))
  end

  it "does not count a support class, a word that starts like one, or a comment", :aggregate_failures do
    others = [
      "class LoaderTest < Minitest::Test\nend\n", "item = 1\n", "examples = []\n", "  def testing\n",
      "# def test_sum\n", "contest \"x\"\n", "a.it { }\n"
    ]
    expect(others.map { |text| count(text) }).to(all(eq(0)))
  end

  it "counts each file once, and none it cannot read" do
    found = files(a: "def test_a\ndef test_b\n", b: "it { }\n", c: "") + [File.join(dir, "gone.rb")]
    expect(described_class.new(found).count).to(eq(2))
  end

  it "reaches the tests and files a glob matches" do
    files("a_test.rb": "", "b_test.rb": "def test_b\n", "other.rb": "def test_c\n")
    expect(described_class.within(dir, "*_test.rb").reach).to(eq([1, 2]))
  end

  it "fails discovery that finds no file, or no file that defines a test", :aggregate_failures do
    expect(described_class.new([]).discovery).to(eq(["✗", described_class::MISSING]))
    testless = "Test discovery: 2 files match tests:, but none defines a test (`def test_…`, `test \"…\"`, `it`); " \
      "fix tests: in .kimera.yml"
    expect(described_class.new(files(a: "", b: "class Base\nend\n")).discovery).to(eq(["✗", testless]))
    expect(described_class.new(files(c: "", d: "it { }\n")).discovery).to(eq(["✓", "Test discovery: 2 files"]))
  end
end
