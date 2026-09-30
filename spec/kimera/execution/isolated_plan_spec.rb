# frozen_string_literal: true

require "kimera/execution/isolated_plan"
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
        .to(eq("tests" => ["A#test_one"], "files" => %w[test/a_test.rb]))
    end

    it "is spec for rspec and test for minitest", :aggregate_failures do
      expect(child.helpers).to(eq("spec"))
      expect(child(framework: "minitest").helpers).to(eq("test"))
    end
  end

  describe "#command" do
    let(:ledgers) { ["l.json", "l.json.request", "l.json.pulse"] }

    def bare(locations, registry: nil)
      Dir.mktmpdir do |mirror|
        return plan(registry: registry || self.registry).command(mirror, locations, File.join(mirror, "l.json"))
      end
    end

    def bundled(locations)
      Dir.mktmpdir do |mirror|
        gemfile = File.join(mirror, "Gemfile")
        File.write(gemfile, "source 'https://rubygems.org'\n")
        return [gemfile, *plan.command(mirror, locations, File.join(mirror, "l.json"))]
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

    def mixed
      src = "def a(x, y)\n  x > y\nend\n"
      Kimera::Registry.new(
        points: Kimera::RegistryScan.new.source(src, file: "lib/x.rb").points +
          Kimera::RegistryScan.new.source(src, file: "app/y.rb").points
      )
    end

    it "writes the locations to the request file instead of argv" do
      Dir.mktmpdir do |mirror|
        ledger = File.join(mirror, "l.json")
        many = Array.new(50_000) { |n| "spec/a_spec.rb[1:#{n}]" }
        plan.command(mirror, many, ledger)
        expect(JSON.parse(File.read("#{ledger}.request"))).to(eq("tests" => many, "files" => []))
      end
    end

    it "includes one -I per distinct mutated top dir" do
      _env, argv = bare(["loc"], registry: mixed)
      includes = argv.each_cons(2).filter_map { |flag, value| value if flag == "-I" }
      expect(includes).to(eq(%w[lib app spec]))
    end
  end

  describe "#mutables" do
    def nested
      src = "def a(x, y)\n  x > y\nend\n"
      Kimera::Registry.new(
        points: Kimera::RegistryScan.new.source(src, file: "lib/a.rb").points +
          Kimera::RegistryScan.new.source(src, file: "lib/deep/b.rb").points +
          Kimera::RegistryScan.new.source(src, file: "app/c.rb").points
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
    it "copies sources, links dependencies, empties scratch dirs and skips history", :aggregate_failures do
      expect(placements(%w[lib app spec Gemfile])).to(all(satisfy { |_e, how| how == :copy }))
      expect(placements(%w[vendor node_modules .bundle]).values).to(eq(%i[link link link]))
      expect(placements(%w[tmp log]).values).to(eq(%i[empty empty]))
      expect(placements(%w[.git coverage]).values).to(eq(%i[skip skip]))
    end

    it "copies a would-be link that holds a mutated file, so no mutant writes through it" do
      src = "def a(x, y)\n  x > y\nend\n"
      inside = Kimera::Registry.new(points: Kimera::RegistryScan.new.source(src, file: "vendor/a.rb").points)
      expect(plan(registry: inside).placement("vendor")).to(eq(:copy))
    end
  end
end
