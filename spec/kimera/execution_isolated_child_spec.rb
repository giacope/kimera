# frozen_string_literal: true

require "fileutils"
require "json"
require "kimera/execution/isolated_child_command"
require "open3"
require "rbconfig"
require "tmpdir"

RSpec.describe(Kimera::Execution) do
  let(:dir) { Dir.mktmpdir }
  let(:lib) { File.expand_path("../../lib", __dir__) }

  after { FileUtils.remove_entry(dir) }

  def project(files)
    files.each do |path, text|
      FileUtils.mkdir_p(File.dirname(File.join(dir, path)))
      File.write(File.join(dir, path), text)
    end
  end

  def child(script = "isolated_child.rb") = [RbConfig.ruby, "-rbundler/setup", "-I", lib, File.join(home, script)]

  def home = File.join(lib, "kimera/execution")

  def run_child
    File.write(File.join(dir, "request.json"), JSON.generate(tests: ["spec/sum_spec.rb"]))
    env = { "BUNDLE_GEMFILE" => File.expand_path("../../Gemfile", __dir__) }
    output, status = Open3.capture2e(env, *child, "ledger.json", "request.json", chdir: dir)
    [status.success?, output, JSON.parse(File.read(File.join(dir, "ledger.json")))]
  end

  def run_minitest(tests)
    File.write(File.join(dir, "request.json"), JSON.generate(tests:, files: ["test/sum_test.rb"], first_failure: false))
    env = { "BUNDLE_GEMFILE" => File.expand_path("../../Gemfile", __dir__) }
    Open3.capture2e(env, *child("isolated_child_minitest.rb"), "ledger.json", "request.json", "pulse", chdir: dir)
    [JSON.parse(File.read(File.join(dir, "ledger.json")))["failing"], beats]
  end

  def beats = File.join(dir, "pulse").then { |pulse| File.file?(pulse) ? File.read(pulse) : "" }

  def sums
    "require \"minitest\"\nclass SumTest < Minitest::Test\n  def test_adds = assert_equal(2, 1 + 1)\n  " \
      "def test_fails = assert_equal(3, 1 + 1)\nend\n"
  end

  it "has the isolated Minitest child beat its pulse for each test it runs, and pass over a test it cannot find" do
    project("test/sum_test.rb" => sums)
    expect(run_minitest(%w[SumTest#test_adds SumTest#gone SumTest#test_fails])).to(eq([["SumTest#test_fails"], ".."]))
  end

  def strict = "module Warning\n  def self.warn(message, **) = raise(message.to_s)\nend\n$VERBOSE = true\n"

  def racing = "$loads = ($loads || 0) + 1\nraise \"PG::DuplicateDatabase (simulated)\" if $loads == 1\n"

  it "reports an error raised while the child reads .rspec as a failure outside every test, with its message",
    :aggregate_failures do
    project(
      ".rspec" => "--require spec_helper\n", "spec/spec_helper.rb" => racing,
      "spec/sum_spec.rb" => "RSpec.describe(\"sum\") { it { expect(1 + 1).to(eq(2)) } }\n"
    )
    passed, _output, ledger = run_child
    expect([passed, ledger["failures"], ledger["failing"]]).to(eq([false, 1, []]))
    expect(ledger["load_error"]).to(
      include(
        "An error occurred while loading spec_helper",
        "PG::DuplicateDatabase (simulated)"
      )
    )
  end

  it "has the isolated RSpec child report to its ledger, and print nothing, when the suite raises on warnings" do
    project(
      ".rspec" => "--require spec_helper\n", "spec/spec_helper.rb" => "#{strict}RSpec.configuration.reporter\n",
      "spec/sum_spec.rb" => "RSpec.describe(\"sum\") { it { expect(1 + 1).to(eq(2)) } }\n"
    )
    expect(run_child).to(eq([true, "", { "failures" => 0, "failing" => [] }]))
  end
end
