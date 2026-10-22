# frozen_string_literal: true

require "fileutils"
require "kimera/execution/isolated_plan"
require "kimera/execution/test_filter"
require "kimera/registry/builder"
require "kimera/runtime"
require "json"
require "tmpdir"

# The mirror-and-bake subprocess flow is covered by the integration suite.
RSpec.describe(Kimera::Execution::IsolatedPlan) do
  let(:registry) do
    Kimera::RegistryScan.new.source(<<~RUBY, file: "lib/calc.rb")
      def a(x, y)
        x > y
      end
    RUBY
  end

  let(:point) { registry.points.first }
  let(:mutant_id) { point.mutants.first.id }

  def plan(**over)
    described_class.new(
      registry: registry, root: ".", tests: %w[t1 t2 t3],
      coverage: {}, framework: "rspec", test_files: [],
      **over
    )
  end

  def runtime
    root = File.expand_path(File.join(__dir__, "..", "..", ".."))
    [Kimera::RegistryScan.new(root: root, shielded: false).build([Kimera::Runtime::SOURCE_PATH]), root]
  end

  describe "#tests" do
    it "runs the whole suite for a point whose method also ran while the suite loaded" do
      point.revisit!(Kimera::MutationPoint::BOOT_REASON)
      expect(plan(coverage: { mutant_id => ["spec/a_spec.rb[1:1]"] }).tests(mutant_id, point)).to(eq(%w[t1 t2 t3]))
    end

    # The tests near its file may leave out the earlier test whose state it
    # needs, so an order-reached point keeps the whole suite.
    it "runs the tests near the file for a load-time point, and the whole suite for an order-reached one",
      :aggregate_failures do
      suite = %w[./spec/a_spec.rb[1:1] ./spec/b_spec.rb[1:1]]
      coverage = { mutant_id => ["./spec/a_spec.rb[1:1]"] }
      point.revisit!(Kimera::MutationPoint::BOOT_REASON)
      expect(plan(tests: suite, coverage: coverage).tests(mutant_id, point)).to(eq(["./spec/a_spec.rb[1:1]"]))
      point.revisit!(Kimera::MutationPoint::ORDER_REASON)
      expect(plan(tests: suite, coverage: coverage).tests(mutant_id, point)).to(eq(suite))
    end

    it "runs only the tests a screen keeps of the whole suite, and settles a point it leaves none",
      :aggregate_failures do
      point.revisit!(Kimera::MutationPoint::BOOT_REASON)
      keeps = plan(filter: Kimera::Execution::TestFilter.new(registry: registry, flaky: %w[t2]))
      expect([keeps.tests(mutant_id, point), keeps.settled(mutant_id, point)]).to(eq([%w[t1 t3], nil]))
      none = plan(filter: Kimera::Execution::TestFilter.new(registry: registry, flaky: %w[t1 t2 t3]))
      expect([none.tests(mutant_id, point), none.settled(mutant_id, point).status]).to(eq([[], :no_coverage]))
    end

    def flaky_t2 = Kimera::Execution::TestFilter.new(registry: registry, flaky: %w[t2])

    it "screens the measured covering set too" do
      screened = plan(coverage: { mutant_id => %w[t1 t2] }, filter: flaky_t2)
      expect([screened.tests(mutant_id, point), screened.settled(mutant_id, point)]).to(eq([["t1"], nil]))
    end

    it "settles a point only screened tests cover as no_coverage" do
      flaky = plan(coverage: { mutant_id => ["t2"] }, filter: flaky_t2)
      expect([flaky.tests(mutant_id, point), flaky.settled(mutant_id, point).status]).to(eq([[], :no_coverage]))
    end

    it "leaves an uncovered point to no_coverage" do
      uncovered = plan(filter: flaky_t2)
      expect([uncovered.tests(mutant_id, point), uncovered.settled(mutant_id, point)]).to(eq([nil, nil]))
    end

    it "returns the measured covering set (integer-keyed) when present" do
      p = plan(coverage: { mutant_id => ["spec/a_spec.rb[1:1]"] })
      expect(p.tests(mutant_id, point)).to(eq(["spec/a_spec.rb[1:1]"]))
    end

    it "returns the measured covering set (string-keyed) when present" do
      p = plan(coverage: { mutant_id.to_s => ["spec/a_spec.rb[1:2]"] })
      expect(p.tests(mutant_id, point)).to(eq(["spec/a_spec.rb[1:2]"]))
    end

    it "falls through an empty recorded set to no_coverage for a coverable point" do
      p = plan(coverage: { mutant_id => [] })
      expect(p.tests(mutant_id, point)).to(be_nil)
    end

    it "reports a coverable but untouched point as no_coverage (nil)" do
      expect(plan.tests(mutant_id, point)).to(be_nil)
    end

    # --no-coverage measured nothing, so every test covers every mutant, as warm.
    it "runs the whole suite when no coverage was measured" do
      expect(plan(coverage: nil).tests(mutant_id, point)).to(eq(%w[t1 t2 t3]))
    end

    it "runs a schema-unsafe point against the whole suite (a safe superset)" do
      unsafe = Kimera::RegistryScan.new.source(<<~RUBY, file: "lib/memo.rb")
        def total(a, b)
          @total ||= compute(a > b)
        end
      RUBY
      pt = unsafe.points.find { |x| !x.safe? }
      p = plan(registry: unsafe)
      expect(p.tests(pt.mutants.first.id, pt)).to(eq(%w[t1 t2 t3]))
    end

    # An unsafe point has no live guard, so a touch recorded for its id
    # belongs to another mutant.
    it "ignores recorded coverage for a schema-unsafe point (contamination)" do
      unsafe = Kimera::RegistryScan.new.source(<<~RUBY, file: "lib/memo.rb")
        def total(a, b)
          @total ||= compute(a > b)
        end
      RUBY
      pt = unsafe.points.find { |x| !x.safe? }
      id = pt.mutants.first.id
      p = plan(registry: unsafe, coverage: { id => ["spec/other_spec.rb[1:1]"] })
      expect(p.tests(id, pt)).to(eq(%w[t1 t2 t3]))
    end

    it "runs a mutant in an instrumentation-excluded (protected) file against the whole suite", :aggregate_failures do
      # The runtime selector can't be instrumented, so it has no coverage.
      protected, root = runtime
      pt = protected.points.find(&:safe?)
      p = plan(registry: protected, root: root)
      expect(p.tests(pt.mutants.first.id, pt)).to(eq(%w[t1 t2 t3]))
      expect(pt.file).to(eq("lib/kimera/runtime.rb"))
    end

    # The selector has no guards. A touch recorded for its id comes from a
    # self-hosting spec calling Runtime.active? with a literal id.
    it "ignores recorded coverage for a protected file (self-host contamination)" do
      protected, root = runtime
      pt = protected.points.find(&:safe?)
      id = pt.mutants.first.id
      p = plan(registry: protected, root: root, coverage: { id => ["spec/kimera/runtime_spec.rb[1:2:1]"] })
      expect(p.tests(id, pt)).to(eq(%w[t1 t2 t3]))
    end
  end

  describe "ChildCommand#argv" do
    def child(framework: "rspec", test_files: [])
      described_class::ChildCommand.new(framework: framework, test_files: test_files)
    end

    let(:files) { ["ledger.json", "ledger.json.request", "ledger.json.pulse"] }

    it "passes only the ledger, its request file and its pulse to the rspec child" do
      expect(child.argv("ledger.json")).to(eq([described_class::ChildCommand::CHILD, *files]))
    end

    it "passes only the ledger, its request file and its pulse to the minitest child" do
      minitest = child(framework: "minitest")
      expect(minitest.argv("ledger.json")).to(eq([described_class::ChildCommand::MINITEST_CHILD, *files]))
    end

    it "requests the test ids and the test files" do
      expect(child(framework: "minitest", test_files: %w[test/a_test.rb]).request(["A#test_one"]))
        .to(eq("tests" => ["A#test_one"], "files" => %w[test/a_test.rb], "first_failure" => false))
    end

    it "asks to stop at the first failure only when told to" do
      expect(child.request(["a"], first: true)).to(include("first_failure" => true))
    end

    it "names the mirror's database slot only when it has one" do
      expect([child.request(["a"], slot: 2)["slot"], child.request(["a"]).key?("slot")]).to(eq([2, false]))
    end

    # The same load path the warm run and doctor use, read in the mirror.
    it "puts the test files' folders and the mirror's test and spec on the load path", :aggregate_failures do
      Dir.mktmpdir do |mirror|
        FileUtils.mkdir_p(File.join(mirror, "test"))
        nested = child(framework: "minitest", test_files: %w[lib/x/test/a_test.rb])
        expect([nested.helpers(mirror), child.helpers(mirror)])
          .to(eq([["-I", "lib/x/test", "-I", "test"], ["-I", "test"]]))
      end
    end
  end

  describe "#command" do
    let(:ledgers) { ["l.json", "l.json.request", "l.json.pulse"] }

    def bare(locations, registry: nil)
      Dir.mktmpdir do |mirror|
        FileUtils.mkdir_p(File.join(mirror, "spec"))
        return plan(registry: registry || self.registry).command(mirror, locations, File.join(mirror, "l.json"))
      end
    end

    def bundled(locations, root: Dir.mktmpdir)
      Dir.mktmpdir do |mirror|
        gemfile = File.join(mirror, "Gemfile")
        File.write(gemfile, "source 'https://rubygems.org'\n")
        FileUtils.mkdir_p(File.join(mirror, "spec"))
        return [gemfile, *plan(root: root).command(mirror, locations, File.join(mirror, "l.json"))]
      end
    end

    it "builds a bare ruby command with load-path includes when there is no Gemfile", :aggregate_failures do
      env, argv = bare(["spec/a_spec.rb[1:1]"])
      child = described_class::ChildCommand::CHILD
      expect(env).to(eq("KIMERA" => "1"))
      expect(argv[0...5]).to(eq(["ruby", "-I", "lib", "-I", "spec"]))
      expect(argv[5..].map { |a| File.basename(a) }).to(eq([File.basename(child), *ledgers]))
    end

    it "wraps in `bundle exec` and pins BUNDLE_GEMFILE when the mirror has a Gemfile", :aggregate_failures do
      gemfile, env, argv = bundled(["spec/a_spec.rb[1:1]"])
      child = described_class::ChildCommand::CHILD
      expect(env).to(eq("KIMERA" => "1", "BUNDLE_GEMFILE" => gemfile))
      expect(argv[0...7]).to(eq(%w[bundle exec ruby -I lib -I spec]))
      expect(argv[7..].map { |a| File.basename(a) }).to(eq([File.basename(child), *ledgers]))
    end

    # A Gemfile names gems by paths relative to it (a monorepo's engines); the
    # mirror sits elsewhere, so only the project's own Gemfile resolves them.
    # A `gemspec` line read from the project's Gemfile puts the project's own
    # lib on the load path beside the mirror's (asciidoctor's -w test then sees
    # VERSION defined twice), so a Gemfile that names nothing by a relative
    # path runs from the mirror.
    it "pins BUNDLE_GEMFILE to the mirror's Gemfile when the project's names no gem by a relative path" do
      Dir.mktmpdir do |root|
        File.write(File.join(root, "Gemfile"), "gemspec\ngem 'kimera', path: '/opt/kimera'\n")
        gemfile, env, = bundled(["spec/a_spec.rb[1:1]"], root: root)
        expect(env.fetch("BUNDLE_GEMFILE")).to(eq(gemfile))
      end
    end

    it "pins BUNDLE_GEMFILE to the project's own Gemfile when it has one" do
      Dir.mktmpdir do |root|
        File.write(File.join(root, "Gemfile"), "gem 'engine', path: '../engine'\n")
        _gemfile, env, = bundled(["spec/a_spec.rb[1:1]"], root: root)
        expect(env.fetch("BUNDLE_GEMFILE")).to(eq(File.join(root, "Gemfile")))
      end
    end

    # The lockfile says where each path gem resolved, however the Gemfile
    # spells it (`path: ENV.fetch("KIMERA_PATH", "../..")`): only a relative
    # path out of the project needs the project's Gemfile; one inside it, or
    # an absolute one, resolves from the mirror too.
    def locked(remotes)
      Dir.mktmpdir do |root|
        File.write(File.join(root, "Gemfile"), "gem 'kimera', path: ENV.fetch('KIMERA_PATH', 'engines/kimera')\n")
        lock = remotes.map { |remote| "PATH\n  remote: #{remote.sub("ROOT", File.basename(root))}\n  specs:\n" }.join
        File.write(File.join(root, "Gemfile.lock"), lock)
        gemfile, env, = bundled(["spec/a_spec.rb[1:1]"], root: root)
        return env.fetch("BUNDLE_GEMFILE") == gemfile ? :mirror : :project
      end
    end

    it "pins BUNDLE_GEMFILE by where the lockfile's path gems resolved", :aggregate_failures do
      expect(locked(["../.."])).to(eq(:project))
      expect(locked([".", "engines/kimera", "/opt/kimera", "../ROOTx"])).to(eq(:project))
      expect(locked([".", "engines/kimera", "/opt/kimera", "engines/../lib"])).to(eq(:mirror))
      expect(locked([])).to(eq(:mirror))
    end

    def mixed
      code = "def a(x, y)\n  x > y\nend\n"
      Kimera::Registry.new(
        points: Kimera::RegistryScan.new.source(code, file: "lib/x.rb").points +
          Kimera::RegistryScan.new.source(code, file: "app/y.rb").points
      )
    end

    it "writes the locations to the request file instead of argv" do
      Dir.mktmpdir do |mirror|
        many = Array.new(50_000) { |n| "spec/a_spec.rb[1:#{n}]" }
        plan.command(mirror, many, File.join(mirror, "l.json"), first: true)
        expect(JSON.parse(File.read(File.join(mirror, "l.json.request"))))
          .to(eq("tests" => many, "files" => [], "first_failure" => true))
      end
    end

    # Only a mutant's run stops at its first failure; a baseline names every failing test.
    it "asks the child to run every test unless told otherwise" do
      Dir.mktmpdir do |mirror|
        ledger = File.join(mirror, "l.json")
        plan.command(mirror, ["spec/a_spec.rb[1:1]"], ledger)
        expect(JSON.parse(File.read("#{ledger}.request"))).to(include("first_failure" => false))
      end
    end

    it "includes one -I per distinct mutated top dir" do
      _env, argv = bare(["loc"], registry: mixed)
      includes = argv.each_cons(2).filter_map { |flag, value| value if flag == "-I" }
      expect(includes).to(eq(%w[lib app spec]))
    end
  end

  describe "#fastest" do
    it "orders tests by their baseline time, keeping the given order without one", :aggregate_failures do
      expect(plan(timings: { "t1" => 2.0, "t3" => 0.1 }).fastest(%w[t1 t2 t3])).to(eq(%w[t3 t1 t2]))
      expect(plan.fastest(%w[t2 t1])).to(eq(%w[t2 t1]))
    end
  end

  describe "#mutables" do
    def nested
      code = "def a(x, y)\n  x > y\nend\n"
      Kimera::Registry.new(
        points: Kimera::RegistryScan.new.source(code, file: "lib/a.rb").points +
          Kimera::RegistryScan.new.source(code, file: "lib/deep/b.rb").points +
          Kimera::RegistryScan.new.source(code, file: "app/c.rb").points
      )
    end

    it "is the distinct first path segment of every mutated file" do
      expect(plan(registry: nested).mutables).to(eq(%w[lib app]))
    end
  end

  describe "#placement" do
    def placements(entries)
      entries.to_h { |entry| [entry, plan.placement(entry)] }
    end

    # A boot that needs node_modules/ or a vendored bundle must load in the
    # mirror, or every mutant it covers scores as a false kill.
    it "copies sources, links dependencies, empties scratch dirs and snapshots history", :aggregate_failures do
      expect(placements(%w[lib app spec Gemfile])).to(all(satisfy { |_e, how| how == :copy }))
      expect(placements(%w[vendor node_modules .bundle]).values).to(eq(%i[link link link]))
      expect(placements(%w[tmp log]).values).to(eq(%i[empty empty]))
      expect(placements(%w[.git coverage]).values).to(eq(%i[git skip]))
    end

    it "copies a would-be link that holds a mutated file, so no mutant writes through it" do
      code = "def a(x, y)\n  x > y\nend\n"
      inside = Kimera::Registry.new(points: Kimera::RegistryScan.new.source(code, file: "vendor/a.rb").points)
      expect(plan(registry: inside).placement("vendor")).to(eq(:copy))
    end
  end
end
