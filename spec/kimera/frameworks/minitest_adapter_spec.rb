# frozen_string_literal: true

require "fileutils"
require "kimera/frameworks/minitest_adapter"
require "tmpdir"

RSpec.describe(Kimera::Frameworks::MinitestAdapter) do
  subject(:adapter) { described_class.build.source([testfile]) }

  let(:dir) { Dir.mktmpdir }

  def testfile
    path = File.join(dir, "demo_test.rb")
    File.write(path, <<~RUBY)
      require "minitest"
      class DemoKimeraTest < Minitest::Test
        def test_passes
          assert_equal 2, 1 + 1
        end
        def test_conditional
          assert_equal true, $probe
        end
        def test_skipped
          skip "nope"
        end
        def test_raises
          explode
        end
        def explode = raise("kaboom")
      end
    RUBY
    path
  end

  # So the next example's source re-evaluates the class fresh.
  def undefine
    Object.__send__(:remove_const, :DemoKimeraTest) if defined?(DemoKimeraTest)
  end

  def flag(value)
    $probe = value
  end

  def state(value)
    flag(value)
    yield
  ensure
    flag(nil)
  end

  after do
    undefine
    FileUtils.remove_entry(dir)
  end

  it "enumerates Class#method test ids" do
    ids = ["DemoKimeraTest#test_passes", "DemoKimeraTest#test_conditional", "DemoKimeraTest#test_skipped"]
    expect(adapter.test_ids).to(include(*ids))
  end

  it "reports a passing run as passed with no failures", :aggregate_failures do
    outcome = adapter.run(["DemoKimeraTest#test_passes"])
    expect(outcome.passed?).to(be(true))
    expect(outcome.failed_ids).to(be_empty)
  end

  it "reports a failing test as a kill", :aggregate_failures do
    outcome = state(false) { adapter.run(["DemoKimeraTest#test_conditional"]) }
    expect(outcome.passed?).to(be(false))
    expect(outcome.failed_ids).to(eq(["DemoKimeraTest#test_conditional"]))
  end

  it "formats a failure message as AssertionClass: message", :aggregate_failures do
    id = "DemoKimeraTest#test_conditional"
    message = state(false) { adapter.run([id]).failures[id] }
    expect(message).to(be_a(String))
    expect(message).to(start_with("Assertion: "))
    expect(message).to(include("Expected"))
  end

  # A warm kill's detail says where the test failed, not just that it did.
  it "follows an assertion's message with the test's own frame", :aggregate_failures do
    id = "DemoKimeraTest#test_conditional"
    message = state(false) { adapter.run([id]).failures[id] }
    lines = message.lines(chomp: true)
    expect(lines.first).to(eq("Assertion: Expected: true"))
    expect(lines.last).to(eq("    #{dir}/demo_test.rb:7:in 'DemoKimeraTest#test_conditional'"))
  end

  it "names an unexpected error's class once, then where it was raised" do
    lines = adapter.run(["DemoKimeraTest#test_raises"]).failures["DemoKimeraTest#test_raises"].lines(chomp: true)
    expect(lines).to(
      eq(
        [
          "UnexpectedError: RuntimeError: kaboom",
          "    #{dir}/demo_test.rb:15:in 'DemoKimeraTest#explode'",
          "    #{dir}/demo_test.rb:13:in 'DemoKimeraTest#test_raises'"
        ]
      )
    )
  end

  it "treats a skip as neither a pass signal nor a kill", :aggregate_failures do
    outcome = adapter.run(["DemoKimeraTest#test_skipped"])
    expect(outcome.passed?).to(be(true))
    expect(outcome.failed_ids).to(be_empty)
  end

  it "re-runs reliably across changing state (fresh instance per run)" do
    passing = state(true) { adapter.run(["DemoKimeraTest#test_conditional"]).passed? }
    failing = state(false) { adapter.run(["DemoKimeraTest#test_conditional"]).passed? }
    expect([passing, failing]).to(eq([true, false]))
  end

  it "ignores unknown ids" do
    expect(adapter.run(["DemoKimeraTest#no_such"]).passed?).to(be(true))
  end

  it "reproduces failing ids with a plain Minitest command, not rspec" do
    expect(adapter.reproduce(["DemoKimeraTest#test_passes", "Nope#test_x"])).to(
      eq(
        "bundle exec ruby -Itest -rminitest/autorun -e 'require File.expand_path(#{testfile.dump})' " \
          "-- -n '/^(?:DemoKimeraTest\\#test_passes|Nope\\#test_x)$/' --seed 1"
      )
    )
  end

  it "shell-quotes single quotes and names files relative to the working directory", :aggregate_failures do
    Dir.chdir(dir) do
      expect(adapter.reproduce(["It's#test"])).to(include("-n '/^(?:It'\\''s\\#test)$/'"))
      expect(adapter.reproduce(["DemoKimeraTest#test_passes"])).to(include("File.expand_path(\"demo_test.rb\")"))
    end
  end

  it "catalogs a test by its id and the file:line that defines it", :aggregate_failures do
    Dir.chdir(dir) do
      catalog = adapter.catalog(["DemoKimeraTest#test_passes", "Nope#test_x"])
      named = { "name" => "DemoKimeraTest#test_passes", "location" => "demo_test.rb:3" }
      expect(catalog).to(eq("DemoKimeraTest#test_passes" => named))
    end
  end

  it "describes an id as itself" do
    expect(adapter.describe("DemoKimeraTest#test_passes")).to(eq("DemoKimeraTest#test_passes"))
  end

  it "falls back to neutering Minitest.run when the autorun internal is absent", :aggregate_failures do
    allow(Minitest).to(receive(:class_variable_set).and_raise(NameError))
    expect { described_class.build }.not_to(raise_error)
    expect(Minitest.run).to(be(true))
  end

  # `rails test` puts test/ on $LOAD_PATH for `require "test_helper"`; kimera loads files directly.
  describe "test/ on $LOAD_PATH" do
    around do |example|
      original = $LOAD_PATH.dup
      example.run
    ensure
      $LOAD_PATH.replace(original)
    end

    def paths(instance, files)
      instance.__send__(:paths, files)
    end

    def root
      File.join(dir, "test")
    end

    def fixture(*parts, content: "")
      path = File.join(root, *parts)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, content)
      path
    end

    it "prepends the test/ directory derived from a test file's path" do
      file = fixture("models", "thing_test.rb")
      paths(described_class.build, [file])
      expect($LOAD_PATH).to(include(root))
    end

    it "adds a test root only once across repeated loads" do
      file = fixture("dup_test.rb")
      ad = described_class.build
      2.times { paths(ad, [file]) }
      expect($LOAD_PATH.count(root)).to(eq(1))
    end

    it "leaves the load path alone for files outside test/ and spec/", :aggregate_failures do
      before = $LOAD_PATH.dup
      expect { paths(described_class.build, ["/kimera-nowhere/thing_test.rb"]) }.not_to(raise_error)
      expect($LOAD_PATH).to(eq(before))
    end

    def helper
      fixture("test_helper.rb", content: "$probe = true\n")
      fixture("uses_helper_test.rb", content: %(require "test_helper"\n))
    end

    it "loads a test file that requires a helper resolved via the added path", :aggregate_failures do
      file = helper
      expect { described_class.build.source([file]) }.not_to(raise_error)
      expect($probe).to(be(true))
    ensure
      $probe = nil
    end
  end

  describe "loading test files" do
    def write(name, body)
      File.join(dir, name).tap { |path| File.write(path, body) }
    end

    it "loads a test file once even when another test requires it", :aggregate_failures do
      shared = write("shared_kimera_test.rb", "$probe = ($probe || 0) + 1\n")
      other = write("other_kimera_test.rb", "require_relative 'shared_kimera_test'\n")
      $probe = 0
      described_class.build.source([shared, other])
      expect($probe).to(eq(1))
    end

    it "hides kimera's own ARGV from test files" do
      probe = write("argv_kimera_test.rb", "$probe = ARGV.dup\n")
      ARGV.replace(%w[run --session x])
      described_class.build.source([probe])
      expect($probe).to(eq([]))
    end

    it "names the test file that fails to load" do
      broken = write("broken_kimera_test.rb", "raise 'boom'\n")
      expect { described_class.build.source([broken]) }
        .to(raise_error(Kimera::Error, /broken_kimera_test\.rb \(RuntimeError: boom\)/))
    end
  end
end
