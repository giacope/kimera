# frozen_string_literal: true

require "fileutils"
require "kimera/frameworks/minitest_suite"
# Examples stub Minitest before any adapter is built, so load it here, not by
# whichever example happens to run first.
require "minitest"
require "tmpdir"

using PointFields

RSpec.describe(Kimera::Frameworks::MinitestSuite) do
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
          assert_equal true, ENV.key?("KIMERA_PROBE")
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

  def state(value, &) = steer(value, &)

  # So each example's source evaluates the class fresh.
  before { stub_const("DemoKimeraTest", Class.new(Minitest::Test)) }

  after do
    FileUtils.remove_entry(dir)
  end

  # R5-KL6: resque's helper stops the Redis it started in Minitest.after_run.
  describe "the suite's after_run hooks" do
    around do |example|
      kept = Minitest.class_variable_get(:@@after_run)
      Minitest.class_variable_set(:@@after_run, [])
      example.run
    ensure
      Minitest.class_variable_set(:@@after_run, kept)
    end

    it "runs them once, last registered first, in the process that loaded the suite" do
      ran = []
      Minitest.after_run { ran << :first }
      Minitest.after_run { ran << :second }
      2.times { adapter.hooks.finish }
      expect(ran).to(eq(%i[second first]))
    end

    # Hooks that, run last registered first, raise, exit and record.
    def troubled(ran)
      Minitest.after_run { ran << :last }
      Minitest.after_run { exit(1) }
      Minitest.after_run { raise(ArgumentError, "no redis") }
    end

    def told
      here = Regexp.escape(__FILE__.delete_prefix("#{Dir.pwd}/"))
      /hook at #{here}:\d+ raised ArgumentError: no redis; kimera went on\n.+ called exit\(1\); kimera went on/
    end

    # CodeTriage: SimpleCov's hook saw kimera's error in flight and exited 1, so the run ended without a word.
    it "goes on past a hook that exits or raises, and says which", :aggregate_failures do
      ran = []
      troubled(ran)
      expect { adapter.hooks.finish }.to(output(told).to_stderr)
      expect(ran).to(eq([:last]))
    end

    # A hook registered from a file under a simplecov gem's lib/.
    def coverage_hook
      hook = File.join(dir, "simplecov-1.3.2", "lib", "simplecov.rb")
      FileUtils.mkdir_p(File.dirname(hook))
      File.write(hook, "Minitest.after_run { KimeraCoverageProbe << :coverage }\n")
      load(hook)
    end

    it "leaves out SimpleCov's own hook, which would write the coverage of kimera's process" do
      probe = stub_const("KimeraCoverageProbe", [])
      coverage_hook
      Minitest.after_run { probe << :suite }
      adapter.hooks.finish
      expect(probe).to(eq([:suite]))
    end

    # The suite loads here; the hooks write to a pipe the forked worker shares.
    # Finishes +loaded+ in a worker forked from this process.
    def forked_finish(loaded)
      Process.wait(
        fork do
          loaded.hooks.finish
        ensure
          exit!(0)
        end
      )
    end

    it "leaves them to that process: a worker forked from it does not run them" do
      reader, writer = IO.pipe
      Minitest.after_run { writer.write("ran") }
      forked_finish(adapter)
      writer.close
      expect(reader.read).to(eq(""))
    end
  end

  # R6B3-M1: the suite loads with the warnings the Rakefile's test task runs it with.
  def warned(rakefile)
    before = [$VERBOSE, Warning[:deprecated]]
    $VERBOSE = false
    Warning[:deprecated] = false
    File.write(File.join(dir, "Rakefile"), rakefile)
    File.write(File.join(dir, "blank_test.rb"), "")
    Dir.chdir(dir) { described_class.build.source(["blank_test.rb"]) }
    [$VERBOSE, Warning[:deprecated]]
  ensure
    $VERBOSE, Warning[:deprecated] = before
  end

  it "loads the suite with warnings on when the Rakefile's test task runs ruby -w", :aggregate_failures do
    expect(warned("Rake::TestTask.new\n")).to(eq([true, true]))
    expect(warned("Rake::TestTask.new { |t| t.warning = false }\n")).to(eq([false, false]))
  end

  it "enumerates Class#method test ids" do
    ids = ["DemoKimeraTest#test_passes", "DemoKimeraTest#test_conditional", "DemoKimeraTest#test_skipped"]
    expect(adapter.test_ids).to(include(*ids))
  end

  def declared
    File.join(dir, "declared_test.rb").tap do |path|
      File.write(
        path,
        "require 'minitest'\nclass KimeraDeclared::FileTest < Minitest::Test\n  def test_it = pass\nend\n"
      )
    end
  end

  # Strict attribution maps each test to the file that declares its class.
  it "names the file that declares a test's class", :aggregate_failures do
    stub_const("KimeraDeclared", Module.new)
    sourced = described_class.build.source([declared])
    expect(sourced["KimeraDeclared::FileTest#test_it"].file).to(eq(File.join(dir, "declared_test.rb")))
    expect(sourced["NoSuchTest#test_x"].file).to(eq(""))
  end

  it "falls back to the test method's file for a class with no constant name" do
    anonymous = Class.new(Minitest::Test) { define_method(:test_it) { true } }
    adapter.instance_variable_get(:@_indexed)["anon#test_it"] = [anonymous, :test_it]
    expect(adapter["anon#test_it"].file).to(eq(__FILE__.delete_prefix("#{Dir.pwd}/")))
  ensure
    Minitest::Runnable.runnables.delete(anonymous)
  end

  describe "a test class whose name is no constant" do
    let(:named) do
      Class.new(Minitest::Test) { define_method(:test_it) { true } }
        .tap { |klass| klass.define_singleton_method(:name) { "a described thing" } }
    end

    after { Minitest::Runnable.runnables.delete(named) }

    it "falls back to the test method's file" do
      adapter.instance_variable_get(:@_indexed)["named#test_it"] = [named, :test_it]
      expect(adapter["named#test_it"].file).to(eq(__FILE__.delete_prefix("#{Dir.pwd}/")))
    end
  end

  def drawn(seed) = seeded(seed) { [adapter.run(["DemoKimeraTest#test_passes"]), rand(1_000_000)].last }

  # Minitest seeds a class's random numbers by the run's seed as it orders
  # the class's tests; kimera's seed for the test follows that.
  it "seeds a test's random numbers by the run's seed and its id, or as Minitest orders it", :aggregate_failures do
    adapter
    seed = Kimera::Seed.new("KIMERA_SEED" => "42").for("DemoKimeraTest#test_passes").fetch(0)
    expected = Random.new(seed).rand(1_000_000)
    expect([drawn(42), drawn(42)]).to(eq([expected, expected]))
    expect(drawn(nil)).to(eq(DemoKimeraTest.runnable_methods.then { rand(1_000_000) }))
  end

  describe "once given the run's seed" do
    around do |example|
      saved = Minitest.seed
      example.run
    ensure
      Minitest.seed = saved
    end

    it "orders and reproduces the suite by it", :aggregate_failures do
      stub_const("DemoKimeraTest", Class.new(Minitest::Test))
      seeded(77) { described_class.build.source([testfile]) }
      expect(Minitest.seed).to(eq(77))
      expect(adapter["DemoKimeraTest#test_passes"].to_s).to(end_with("--seed 77"))
    end
  end

  it "indexes the tests its files defined when it sourced them, not a class defined later" do
    sourced = adapter
    later = Class.new(Minitest::Test) { define_method(:test_later) { pass } }
    expect(sourced.test_ids).not_to(include("#{later}#test_later"))
  end

  it "reports a passing run as passed with no failures", :aggregate_failures do
    outcome = adapter.run(["DemoKimeraTest#test_passes"])
    expect(outcome.passed?).to(be(true))
    expect(outcome.to_h.fetch("failed_ids")).to(be_empty)
  end

  it "reports a failing test as a kill", :aggregate_failures do
    outcome = state(false) { adapter.run(["DemoKimeraTest#test_conditional"]) }
    expect(outcome.passed?).to(be(false))
    expect(outcome.to_h.fetch("failed_ids")).to(eq(["DemoKimeraTest#test_conditional"]))
  end

  it "formats a failure message as AssertionClass: message", :aggregate_failures do
    id = "DemoKimeraTest#test_conditional"
    message = state(false) { adapter.run([id]).to_h.fetch("failures")[id] }
    expect(message).to(be_a(String))
    expect(message).to(start_with("Assertion: "))
    expect(message).to(include("Expected"))
  end

  # A warm kill's detail says where the test failed, not just that it did.
  it "follows an assertion's message with the test's own frame", :aggregate_failures do
    id = "DemoKimeraTest#test_conditional"
    message = state(false) { adapter.run([id]).to_h.fetch("failures")[id] }
    lines = message.lines(chomp: true)
    expect(lines.first).to(eq("Assertion: Expected: true"))
    expect(lines.last).to(eq("    #{dir}/demo_test.rb:7:in 'DemoKimeraTest#test_conditional'"))
  end

  it "names an unexpected error's class once, then where it was raised" do
    failures = adapter.run(["DemoKimeraTest#test_raises"]).to_h.fetch("failures")
    lines = failures["DemoKimeraTest#test_raises"].lines(chomp: true)
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
    expect(outcome.to_h.fetch("failed_ids")).to(be_empty)
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
    FileUtils.mkdir_p(File.join(dir, "test"))
    command = Dir.chdir(dir) { adapter["DemoKimeraTest#test_passes", "Nope#test_x"].to_s }
    expect(command).to(
      eq(
        "bundle exec ruby -Itest -rminitest/autorun -e 'require File.expand_path(\"demo_test.rb\")' " \
          "-- -n '/^(?:DemoKimeraTest\\#test_passes|Nope\\#test_x)$/' --seed 1"
      )
    )
  end

  # The command must load what kimera loaded: a nested test folder and the
  # project's root test/ both, quoted where the shell needs it.
  # A test file in a folder whose name holds a space, beside a test folder.
  def nested_test
    nested = File.join(dir, "lib", "my tool", "test")
    FileUtils.mkdir_p([nested, File.join(dir, "test")])
    File.join(nested, "nested_test.rb").tap do |file|
      File.write(file, <<~RUBY)
        require 'minitest'
        class NestedKimeraTest < Minitest::Test
          def test_it = assert(true)
        end
      RUBY
    end
  end

  it "puts every folder kimera loaded tests from on the reproduce command's load path" do
    stub_const("NestedKimeraTest", Class.new(Minitest::Test))
    file = nested_test
    command = Dir.chdir(dir) { described_class.build.source([file])["NestedKimeraTest#test_it"].to_s }
    expect(command).to(start_with("bundle exec ruby -I'lib/my tool/test' -Itest -rminitest/autorun -e "))
  end

  it "shell-quotes single quotes and names files relative to the working directory", :aggregate_failures do
    Dir.chdir(dir) do
      expect(adapter["It's#test"].to_s).to(include("-n '/^(?:It'\\''s\\#test)$/'"))
      expect(adapter["DemoKimeraTest#test_passes"].to_s).to(include("File.expand_path(\"demo_test.rb\")"))
    end
  end

  it "catalogs a test by its id and the file:line that defines it", :aggregate_failures do
    Dir.chdir(dir) do
      catalog = adapter["DemoKimeraTest#test_passes", "Nope#test_x"].to_h
      named = { "name" => "DemoKimeraTest#test_passes", "location" => "demo_test.rb:3" }
      expect(catalog).to(eq("DemoKimeraTest#test_passes" => named))
    end
  end

  it "describes an id as itself" do
    expect(adapter["DemoKimeraTest#test_passes"].name).to(eq("DemoKimeraTest#test_passes"))
  end

  # A Minitest without the autorun internal, and no run of its own, in place of the real one for the example.
  def bare_minitest
    minitest =
      Module.new do
        singleton_class.attr_accessor(:seed)
        def self.class_variable_set(*) = raise(NameError, "uninitialized class variable @@installed_at_exit")
      end
    stub_const("Minitest", minitest.tap { |fake| fake.const_set(:Test, Class.new) })
  end

  it "falls back to neutering Minitest.run when the autorun internal is absent", :aggregate_failures do
    bare_minitest
    expect { described_class.build }.not_to(raise_error)
    expect(Minitest.run).to(be(true))
  end

  # This file loads Minitest itself, so a fresh process shows the build loads it.
  it "loads Minitest when it builds" do
    loads = fresh_lines(<<~RUBY)
      require "kimera/frameworks/minitest_suite"
      p(defined?(::Minitest::Test))
      Kimera::Frameworks::MinitestSuite.build
      p(defined?(::Minitest::Test))
    RUBY
    expect(loads).to(eq(["nil", '"constant"']))
  end

  # minitest-hooks builds each test from an instance its with_info_handler
  # makes, so a test run outside that handler cannot even be constructed.
  describe "class-level hooks" do
    def hooked(before_all: "true")
      path = File.join(dir, "hooked_test.rb")
      File.write(path, <<~RUBY)
        require "minitest"
        class HookedKimeraTest < Minitest::Test
          def self.with_info_handler(reporter, &block)
            @instance = :ready
            if #{before_all}
              super
            else
              failed = new("test_ok")
              failed.failures << Minitest::Assertion.new("before_all failed")
              reporter.record(failed)
            end
          ensure
            @instance = nil
          end
          def self.new(name)
            raise(FrozenError, "can't modify frozen NilClass") unless @instance
            super
          end
          def test_ok = assert(true)
          def test_bad = assert(false)
        end
      RUBY
      described_class.build.source([path])
    end

    before { stub_const("HookedKimeraTest", Class.new(Minitest::Test)) }

    it "runs each test inside its class's info handler", :aggregate_failures do
      outcome = hooked.run(["HookedKimeraTest#test_ok", "HookedKimeraTest#test_bad"])
      expect(outcome.to_h.fetch("failures").keys).to(eq(["HookedKimeraTest#test_bad"]))
    end

    it "fails a test whose class hook failed before it ran" do
      outcome = hooked(before_all: "false").run(["HookedKimeraTest#test_ok"])
      expect(outcome.to_h.fetch("failures")["HookedKimeraTest#test_ok"]).to(include("before_all failed"))
    end
  end

  describe "a test whose class's info handler never ran it" do
    let(:silent) do
      Class.new(Minitest::Test) do
        define_singleton_method(:with_info_handler) { |*| :skipped }
        define_method(:test_it) { flunk }
      end
    end

    after { Minitest::Runnable.runnables.delete(silent) }

    it "passes" do
      adapter.instance_variable_get(:@_indexed)["silent#test_it"] = [silent, :test_it]
      expect(adapter.run(["silent#test_it"]).passed?).to(be(true))
    end
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
      fixture("test_helper.rb", content: "PROBE << :helper\n")
      fixture("uses_helper_test.rb", content: %(require "test_helper"\n))
    end

    it "loads a test file that requires a helper resolved via the added path", :aggregate_failures do
      file = helper
      expect { described_class.build.source([file]) }.not_to(raise_error)
      expect(probed).to(eq([:helper]))
    end
  end

  describe "loading test files" do
    def write(name, body)
      File.join(dir, name).tap { |path| File.write(path, body) }
    end

    it "loads a test file once even when another test requires it", :aggregate_failures do
      shared = write("shared_kimera_test.rb", "PROBE << :loaded\n")
      other = write("other_kimera_test.rb", "require_relative 'shared_kimera_test'\n")
      described_class.build.source([shared, other])
      expect(probed).to(eq([:loaded]))
    end

    it "hides kimera's own ARGV from test files" do
      probe = write("argv_kimera_test.rb", "PROBE << ARGV.dup\n")
      ARGV.replace(%w[run --session x])
      described_class.build.source([probe])
      expect(probed).to(eq([[]]))
    end

    it "names the test file that fails to load" do
      broken = write("broken_kimera_test.rb", "raise 'boom'\n")
      expect { described_class.build.source([broken]) }
        .to(raise_error(Kimera::Error, /broken_kimera_test\.rb \(RuntimeError: boom\)/))
    end
  end
end
