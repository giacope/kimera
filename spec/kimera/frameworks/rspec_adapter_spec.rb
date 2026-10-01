# frozen_string_literal: true

require "fileutils"
require "kimera/frameworks/rspec_adapter"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::Frameworks::RSpecAdapter) do
  # Hides RSpec's warning about re-pointing already-initialized streams.
  def quietly
    original = $stderr
    $stderr = StringIO.new
    yield
  ensure
    $stderr = original
  end

  subject(:adapter) { quietly { described_class.build.source([fixture]) } }

  let(:dir) { Dir.mktmpdir }
  # Suite hooks are global; a leaked after(:suite) would fire at the end of Kimera's own suite.
  let(:attributes) { %i[@before_suite_hooks @after_suite_hooks].freeze }

  after { FileUtils.remove_entry(dir) }

  # Loading a spec file registers groups in the global RSpec.world, so snapshot and restore it.
  around do |example|
    groups = RSpec.world.example_groups.dup
    out = RSpec.configuration.output_stream
    error = RSpec.configuration.error_stream
    deprecation = RSpec.configuration.deprecation_stream
    hooks =
      attributes.to_h do |attribute|
        [attribute, RSpec.configuration.instance_variable_get(attribute).dup]
      end
    example.run
  ensure
    (RSpec.world.example_groups - groups).each do |group|
      RSpec.world.example_groups.delete(group)
    end
    RSpec.configuration.output_stream = out
    RSpec.configuration.error_stream = error
    RSpec.configuration.deprecation_stream = deprecation
    hooks.each { |attribute, callbacks| RSpec.configuration.instance_variable_set(attribute, callbacks) }
  end

  def fixture
    path = File.join(dir, "demo_spec.rb")
    File.write(path, <<~RUBY)
      RSpec.describe "KimeraDemo" do
        it "passes" do
          expect(1 + 1).to eq(2)
        end
        it "is conditional" do
          expect($probe).to be(true)
        end
        describe "nested" do
          it "also passes" do
            expect(true).to be(true)
          end
        end
      end
    RUBY
    path
  end

  def ids
    adapter.test_ids.select { |id| adapter.describe(id).start_with?("KimeraDemo") }
  end

  def flag(value)
    $probe = value

    yield
  ensure
    $probe = nil
  end

  it "indexes loaded examples, including nested groups" do
    descriptions = ids.map { |id| adapter.describe(id) }
    expect(descriptions).to(include("KimeraDemo passes", "KimeraDemo is conditional", "KimeraDemo nested also passes"))
  end

  it "describes an unknown id as itself" do
    expect(adapter.describe("no/such[1:1]")).to(eq("no/such[1:1]"))
  end

  def guarded
    path = File.join(dir, "guarded_spec.rb")
    File.write(path, <<~RUBY)
      RSpec.describe "KimeraGuarded", if: false do
        it "must never be indexed" do
          raise "filtered-out example was executed"
        end
      end
    RUBY
    path
  end

  # Backend-gated suites use `if: ENV["DB_URL"]`; running them anyway fails the baseline on skipped setup.
  it "does not index examples the real runner would filter out (:if false)" do
    filtered = quietly { described_class.build.source([guarded]) }
    indexed = filtered.test_ids.select { |id| filtered.describe(id).start_with?("KimeraGuarded") }
    expect(indexed).to(be_empty)
  end

  def recorder
    ran = []
    RSpec.configuration.before(:suite) { ran << :before }
    RSpec.configuration.after(:suite) { ran << :after }
    ran
  end

  # Running groups directly skips suite hooks, where e.g. webmock/rspec calls WebMock.enable!.
  it "does not fire suite hooks merely from finishing without starting" do
    ran = recorder
    described_class.build.finish
    expect(ran).to(be_empty)
  end

  def twice
    fresh = described_class.build
    2.times { fresh.start }
    fresh.finish
  end

  it "fires before(:suite) once and after(:suite) only once starting has happened" do
    ran = recorder
    twice
    expect(ran).to(eq(%i[before after]))
  end

  it "propagates a raising before(:suite) hook instead of running the suite" do
    RSpec.configuration.before(:suite) { raise(RuntimeError, "backend unavailable") }

    expect { described_class.build.start }.to(raise_error(RuntimeError, "backend unavailable"))
  end

  it "passes when running a green example" do
    id = ids.find { |i| adapter.describe(i) == "KimeraDemo passes" }
    expect(adapter.run([id]).passed?).to(be(true))
  end

  # Callers stay separate examples, not :aggregate_failures. The nested run shares
  # this thread, so the outer aggregator would swallow its failure.
  def outcome(id)
    flag(false) { adapter.run([id]) }
  end

  it "reports a failing example as a kill" do
    id = ids.find { |i| adapter.describe(i) == "KimeraDemo is conditional" }
    expect(outcome(id).passed?).to(be(false))
  end

  it "carries the failing example's id in failed_ids" do
    id = ids.find { |i| adapter.describe(i) == "KimeraDemo is conditional" }
    expect(outcome(id).failed_ids).to(eq([id]))
  end

  it "re-runs the same example reliably across changing state" do
    id = ids.find { |i| adapter.describe(i) == "KimeraDemo is conditional" }
    results = [true, false, true].map { |value| flag(value) { adapter.run([id]).passed? } }
    expect(results).to(eq([true, false, true]))
  end

  def quitting
    RSpec.world.wants_to_quit = true
    yield
  ensure
    RSpec.world.wants_to_quit = false
  end

  # --fail-fast sets wants_to_quit; left set, later runs skip every example and kills become survivals.
  it "clears a stuck fail-fast quit flag so a killing example still runs" do
    id = ids.find { |i| adapter.describe(i) == "KimeraDemo is conditional" }
    outcome = quitting { flag(false) { adapter.run([id]) } }
    expect(outcome.passed?).to(be(false))
  end

  def failure
    RSpec.world.non_example_failure = true
    yield
  ensure
    RSpec.world.non_example_failure = false
  end

  # A raising suite hook sets this; left set, the outer runner exits red although every example passed.
  it "clears a stuck non-example failure flag before each run" do
    id = ids.find { |i| adapter.describe(i) == "KimeraDemo passes" }
    failure { adapter.run([id]) }
    expect(RSpec.world.non_example_failure).to(be(false))
  end

  it "runs examples across sibling and nested groups together" do
    wanted = ["KimeraDemo passes", "KimeraDemo nested also passes"]
    selected = ids.select { |i| wanted.include?(adapter.describe(i)) }
    expect(adapter.run(selected).passed?).to(be(true))
  end

  # Separate examples for the same reason as #outcome.
  def message
    id = ids.find { |i| adapter.describe(i) == "KimeraDemo is conditional" }
    flag(false) { adapter.run([id]).failures[id] }
  end

  it "formats a failure message as ExceptionClass: message" do
    expect(message).to(be_a(String))
  end

  it "prefixes the failure message with the exception class" do
    expect(message).to(start_with("RSpec::Expectations::ExpectationNotMetError: "))
  end

  it "includes the expectation detail in the failure message" do
    expect(message).to(include("expected true"))
  end

  def counted
    path = File.join(dir, "counted_spec.rb")
    File.write(path, <<~RUBY)
      RSpec.describe "KimeraCounted" do
        it("a") { $probe << :a }
        it("b") { $probe << :b }
        describe "inner" do
          it("c") { $probe << :c }
          it("d") { $probe << :d }
        end
      end
    RUBY
    path
  end

  def prepared
    quietly { described_class.build.source([counted]) }
  end

  def executions
    $probe = []

    yield
    $probe
  ensure
    $probe = nil
  end

  # The filtered-examples override, set through the whole tree, is what keeps siblings from running.
  it "executes only the selected example, not its group or nested siblings" do
    ad = prepared
    id = ad.test_ids.find { |i| ad.describe(i) == "KimeraCounted inner c" }
    ran = executions { ad.run([id]) }
    expect(ran).to(eq([:c]))
  end

  def contextual
    path = File.join(dir, "contextual_spec.rb")
    File.write(path, <<~RUBY)
      RSpec.describe "KimeraContextual" do
        it("outside") { $probe << :outside }
        describe "hooked" do
          before(:context) { $probe << :before_context }
          after(:context) { $probe << :after_context }
          it("inside") { $probe << :inside }
        end
      end
    RUBY
    path
  end

  def sequenced(*descriptions)
    ad = quietly { described_class.build.source([contextual]) }
    runs = descriptions.map { |text| ad.test_ids.find { |i| ad.describe(i) == "KimeraContextual #{text}" } }
    executions { runs.each { |id| ad.run([id]) } }
  end

  # RSpec memoizes each group's descendant_filtered_examples. Left from an earlier
  # narrow run, it skips before(:context) (rubocop-ast's alias_matcher) or runs it
  # for a group with nothing selected.
  it "runs a group's context hooks when an earlier run selected none of its examples" do
    expect(sequenced("outside", "hooked inside")).to(eq(%i[outside before_context inside after_context]))
  end

  it "skips a group's context hooks when this run selects none of its examples" do
    expect(sequenced("hooked inside", "outside")).to(eq(%i[before_context inside after_context outside]))
  end

  def overrides(description)
    groups = RSpec.world.example_groups.select { |g| g.description == description }
    RSpec.world.filtered_examples.keys & (groups + groups.flat_map(&:children))
  end

  # Under self-hosting a leftover override would corrupt the outer suite's runs.
  it "removes its filtered-examples overrides once the run finishes" do
    ad = prepared
    id = ad.test_ids.find { |i| ad.describe(i) == "KimeraCounted inner c" }
    executions { ad.run([id]) }
    expect(overrides("KimeraCounted")).to(be_empty)
  end

  def configuration
    File.write(File.join(dir, ".rspec"), "--require ./dotrspec_probe\n")
    File.write(File.join(dir, "dotrspec_probe.rb"), "$probe = true\n")
  end

  # In-process so mutation coverage sees it; the subprocess spec below covers end-to-end.
  it "applies the working directory's .rspec when constructed" do
    configuration
    Dir.chdir(dir) { quietly { described_class.build } }
    expect($probe).to(be(true))
  ensure
    $probe = nil
  end

  it "returns passed for an empty / unknown selection", :aggregate_failures do
    expect(adapter.run([]).passed?).to(be(true))
    expect(adapter.run(["nope[1:1]"]).passed?).to(be(true))
  end

  def probe(root)
    FileUtils.mkdir_p(File.join(root, "spec"))
    File.write(File.join(root, "spec", "probe_helper.rb"), "PROBE_OK = true\n")
    File.write(File.join(root, ".rspec"), "--require probe_helper\n")
    File.write(File.join(root, "spec", "probe_spec.rb"), <<~RUBY)
      RSpec.describe("probe") { it("sees helper") { expect(PROBE_OK).to be(true) } }
    RUBY
  end

  # RSpec can only be configured before it runs, so this needs a fresh subprocess.
  def script(lib)
    <<~RUBY
      $LOAD_PATH.unshift(#{lib.inspect})
      require "kimera/frameworks/rspec_adapter"
      adapter = Kimera::Frameworks::RSpecAdapter.build
      adapter.source(["spec/probe_spec.rb"])
      outcome = adapter.run(adapter.test_ids)
      exit(outcome.passed? ? 0 : 1)
    RUBY
  end

  def subprocess(root)
    lib = File.expand_path("../../../lib", __dir__)
    system(
      { "BUNDLE_GEMFILE" => File.join(lib, "..", "Gemfile") },
      "ruby", "-e", script(lib),
      chdir: root, out: File::NULL, err: File::NULL
    )
  end

  it "honors the project .rspec --require when constructed" do
    Dir.mktmpdir do |root|
      probe(root)
      expect(subprocess(root)).to(be(true))
    end
  end

  describe "narrowing the filtered-example table" do
    def narrow(filtered, wanted, &)
      Kimera::Frameworks::GroupScope.new(wanted).narrow(filtered, &)
    end

    def top
      prepared
      RSpec.world.example_groups.find { |g| g.description == "KimeraCounted" }
    end

    def example(group, text) = group.descendants.flat_map(&:examples).find { |ex| ex.description == text }

    it "scopes only the wanted example's ancestor chain while the block runs", :aggregate_failures do
      outer = top
      inner = outer.children.first
      c = example(outer, "c")
      filtered = {}
      seen = nil
      narrow(filtered, [c]) { seen = filtered.dup }
      expect(seen).to(eq(outer => [], inner => [c]))
      expect(filtered).to(be_empty)
    end

    it "hides children off the chain while the block runs, then restores them", :aggregate_failures do
      outer = top
      inner = outer.children.first
      seen = nil
      narrow({}, [example(outer, "a")]) { seen = outer.children.dup }
      expect(seen).to(be_empty)
      expect(outer.children).to(eq([inner]))
    end

    it "restores entries it did not add, and the children it hid, after a raise", :aggregate_failures do
      outer = top
      inner = outer.children.first
      other = Object.new
      filtered = { other => %i[a b] }
      expect { narrow(filtered, [example(outer, "a")]) { raise(ArgumentError) } }.to(raise_error(ArgumentError))
      expect(filtered).to(eq(other => %i[a b]))
      expect(outer.children).to(eq([inner]))
    end
  end
end
