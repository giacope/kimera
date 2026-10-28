# frozen_string_literal: true

require "fileutils"
require "kimera/execution/schemata"
require "kimera/registry/builder"
require "tmpdir"

RSpec.describe(Kimera::Execution::Schemata) do
  let(:dir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(dir)
  end

  def write(relative, body)
    path = File.join(dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    relative
  end

  def loaded(relative, body) = require(File.join(dir, write(relative, body)))

  def greater(name) = "class #{name}\n  def gt(a, b)\n    a > b\n  end\nend\n"

  def scan(*names) = Kimera::RegistryScan.new(root: dir).build(names.map { |name| File.join(dir, name) })

  def schemata(registry) = described_class.new(registry, root: dir)

  def overlaid(*names)
    registry = scan(*names)
    [registry, schemata(registry).overlay!]
  end

  # What the block returns with the labelled mutant on.
  def flipped(registry, label = "> => <", &)
    Kimera::RUNTIME.during(registry.each.find { |mutant, _point| mutant.label == label }.first.id, &)
  end

  # What the block returns with no mutant active, then with the labelled one.
  def outcomes(registry, label = "> => <", &) = [yield, flipped(registry, label, &)]

  def noisily(loader)
    live = nil
    expect { live = loader.overlay! }.to(output.to_stderr)
    live
  end

  def overlaying(&) = Kimera::Execution::OverlayGuards.new.overlay(&)

  it "overlays schema-safe files and returns the live mutant ids", :aggregate_failures do
    stub_const("SchemataTarget", Class.new)
    write("sl_target.rb", greater("SchemataTarget"))
    registry, live = overlaid("sl_target.rb")
    expect(live).to(match_array(registry.each.map { |m, _p| m.id }))
    expect(outcomes(registry) { SchemataTarget.new.gt(2, 1) }).to(eq([true, false]))
  end

  # Re-running the class body would redeclare its DSL state (here, count the
  # load twice); only the mutated method has to run again.
  it "re-runs only the mutated code of a file that was already required", :aggregate_failures do
    stub_const("SchemataRequired", Class.new)
    loaded("sl_required.rb", <<~RUBY)
      class SchemataRequired
        @loads = (@loads || 0) + 1
        singleton_class.attr_reader(:loads)
        def gt(a, b)
          a > b
        end
      end
    RUBY
    registry, = overlaid("sl_required.rb")
    expect(SchemataRequired.loads).to(eq(1))
    expect(flipped(registry) { SchemataRequired.new.gt(2, 1) }).to(be(false))
  end

  # An alias declared in another file copies the body before the overlay runs;
  # left alone, it keeps calling the unguarded code and no test reaches the
  # mutants through it.
  it "re-points an alias declared in another file at the guarded method" do
    stub_const("SchemataAliased", Module.new)
    loaded("sl_aliased.rb", "module SchemataAliased\n  def gt(a, b)\n    a > b\n  end\nend\n")
    holder = Class.new { include SchemataAliased }.tap { |klass| klass.alias_method(:above, :gt) }
    expect(flipped(overlaid("sl_aliased.rb").first) { holder.new.above(2, 1) }).to(be(false))
  end

  # R6B4-M7: a memoizer in another file (Adamantium's `memoize`) wraps the
  # method in one that calls the original it captured; no test reaches the
  # overlay warm, so its mutants are judged again in a fresh mirror.
  def memoized
    stub_const("SchemataMemo", Class.new)
    loaded("sl_memo.rb", greater("SchemataMemo"))
    memoizer = "SchemataMemo.class_eval do\n  kept = instance_method(:gt)\n  " \
      "define_method(:gt) { |a, b| kept.bind(self).call(a, b) }\nend\n"
    write("sl_memoizer.rb", memoizer)
    require(File.join(dir, "sl_memoizer.rb"))
    overlaid("sl_memo.rb").first
  end

  it "judges again the mutants of a method another file's wrapper holds", :aggregate_failures do
    registry = memoized
    expect(registry.points.map(&:revisit).uniq).to(eq([Kimera::Execution::Overrides::WRAPPED]))
    expect(flipped(registry) { SchemataMemo.new.gt(2, 1) }).to(be(true))
  end

  def chained
    stub_const("SchemataChained", Module.new)
    loaded("sl_chained.rb", "module SchemataChained\n  def gt(a, b)\n    a > b\n  end\nend\n")
    chain = "SchemataChained.module_eval do\n  alias_method :plain_gt, :gt\n  def gt(a, b) = plain_gt(a, b)\nend\n"
    loaded("sl_chain.rb", chain)
    overlaid("sl_chained.rb").first
  end

  it "leaves the mutants an alias of the wrapped method reaches as warm judges them" do
    expect(chained.points.map(&:revisit).uniq).to(eq([nil]))
  end

  # dry-validation requires its extensions on demand. Unregistered, that require
  # loaded the original file over the guarded methods, which hid their mutants.
  describe "a file the suite requires only later" do
    after { $LOADED_FEATURES.reject! { |feature| feature.end_with?("sl_lazy.rb") } }

    def lazily(root)
      registry = Kimera::RegistryScan.new(root: root).build([File.join(root, "sl_lazy.rb")])
      described_class.new(registry, root: root).overlay!
      registry.each.find { |m, _p| m.label == "> => <" }.first.id
    end

    # The file's mutant, and the file by its linked and its real path.
    def lazy
      stub_const("SchemataLazy", Class.new)
      write("real/sl_lazy.rb", greater("SchemataLazy"))
      File.symlink(File.join(dir, "real"), File.join(dir, "linked"))
      [lazily(File.join(dir, "linked")), %w[linked real].map { |root| File.join(dir, root, "sl_lazy.rb") }]
    end

    it "counts as already required by either path" do
      _, paths = lazy
      expect(paths.map { |path| require(path) }).to(eq([false, false]))
    end

    it "keeps its guards when the suite requires it" do
      id, paths = lazy
      paths.each { |path| require(path) }
      expect(Kimera::RUNTIME.during(id) { SchemataLazy.new.gt(2, 1) }).to(be(false))
    end
  end

  it "skips files that have no schema-safe points", :aggregate_failures do
    # Memoized code is never schema-safe.
    write("sl_memo.rb", <<~RUBY)
      class SchemataMemo
        def total(a, b)
          @total ||= compute(a > b)
        end
      end
    RUBY
    registry = Kimera::RegistryScan.new(root: dir).build([File.join(dir, "sl_memo.rb")])
    live = described_class.new(registry, root: dir).overlay!
    expect(live).to(eq([]))
    # Skipped before eval, so the file never runs.
    expect(defined?(SchemataMemo)).to(be_nil)
  end

  def shielded(relative)
    allow(Kimera::SelfProtection).to(receive(:new).and_call_original)
    shield = instance_double(Kimera::SelfProtection, protected?: true)
    allow(Kimera::SelfProtection).to(receive(:new).with(File.join(dir, relative)).and_return(shield))
  end

  it "never overlays a self-protected file" do
    write("sl_protected.rb", greater("SchemataProtected"))
    # The builder checks protected? too, so stub after building.
    registry = scan("sl_protected.rb")
    shielded("sl_protected.rb")
    expect([schemata(registry).overlay!, defined?(SchemataProtected)]).to(eq([[], nil]))
  end

  # Scripts may abort at top level when re-run. SystemExit is not a
  # StandardError, so uncaught it would kill the harness.
  describe "a top-level script that aborts when overlaid" do
    def scripted
      stub_const("SchemataAfter", Class.new)
      write("sl_script.rb", <<~RUBY)
        abort("usage: nope") unless ARGV.include?("--never-there")

        def sl_script_helper(a, b)
          a > b
        end
      RUBY
      write("sl_after.rb", greater("SchemataAfter"))
      registry = scan("sl_script.rb", "sl_after.rb")
      [registry, schemata(registry)]
    end

    # The abort's raw stderr must not leak; the diagnosis line carries it.
    it "is diagnosed on stderr, without its own output" do
      _, loader = scripted
      expect { loader.overlay! }
        .to(output(/\Akimera: sl_script\.rb cannot run in warm workers.*\(SystemExit: usage: nope\)/).to_stderr)
    end

    it "does not stop the files after it" do
      registry, loader = scripted
      point = registry.points.find { |p| p.file == "sl_after.rb" }
      expect(noisily(loader)).to(include(*point.ids))
    end

    # The reason lets callers tell unmutatable files from uncovered mutants.
    it "is skipped with its reason" do
      _, loader = scripted
      noisily(loader)
      expect(loader.skipped).to(include("sl_script.rb" => "SystemExit: usage: nope"))
    end
  end

  it "replays what a successful overlay wrote to stderr", :aggregate_failures do
    stub_const("SchemataWarny", Class.new)
    # $stderr.puts because evaluate silences Kernel#warn via $VERBOSE=nil.
    write("sl_warny.rb", <<~RUBY)
      class SchemataWarny
        $stderr.puts "sl_warny loading"

        def gt(a, b)
          a > b
        end
      end
    RUBY
    loader = schemata(scan("sl_warny.rb"))
    expect { loader.overlay! }.to(output("sl_warny loading\n").to_stderr)
    expect(loader.skipped).to(be_empty)
  end

  describe "a file whose synthesis raises" do
    def synthesized
      stub_const("SchemataSynthOk", Class.new)
      write("sl_synth_bad.rb", greater("SchemataSynthBad"))
      write("sl_synth_ok.rb", greater("SchemataSynthOk"))
      registry = scan("sl_synth_bad.rb", "sl_synth_ok.rb")
      [registry, schemata(registry).tap { |loader| unparseable(loader) }]
    end

    # Synthesis can raise, as on a node kimera can't write.
    def unparseable(loader)
      allow(loader.__send__(:synth)).to(receive(:synthesize).and_wrap_original) do |original, file, source|
        raise(ArgumentError, "kimera cannot write a foo node") if file == "sl_synth_bad.rb"

        original.call(file, source)
      end
    end

    it "is diagnosed on stderr" do
      _, loader = synthesized
      expect { loader.overlay! }.to(output(/sl_synth_bad\.rb cannot run in warm workers.*ArgumentError/).to_stderr)
    end

    it "does not stop the rest from being overlaid", :aggregate_failures do
      registry, loader = synthesized
      point = registry.points.find { |p| p.file == "sl_synth_ok.rb" }
      expect(noisily(loader)).to(include(*point.ids))
      expect(point).to(be_safe)
    end

    it "leaves its points unmutatable, with the reason" do
      registry, loader = synthesized
      noisily(loader)
      reasons = registry.points.select { |p| p.file == "sl_synth_bad.rb" }.map(&:unsafe_reason).uniq
      expect(reasons).to(eq(["unmutatable: schemata setup failed (ArgumentError: kimera cannot write a foo node)"]))
    end
  end

  it "ignores registry files that no longer exist on disk", :aggregate_failures do
    loader = schemata(Kimera::RegistryScan.new(root: dir).source("def m(a, b)\n  a > b\nend\n", file: "vanished.rb"))
    live = nil
    # Absent is not unmutatable: no warning and no skipped entry.
    expect { live = loader.overlay! }.not_to(output.to_stderr)
    expect([live, loader.skipped]).to(eq([[], {}]))
  end

  # The overlay re-runs class bodies, which re-declares defined enums.
  describe "enum overlay guard" do
    let(:plain) do
      Class.new do
        def self.calls = @_calls ||= []

        def self.enum(*arguments, **_kwargs) = calls << arguments
      end
    end
    let(:declared) { Class.new(plain) { def self.defined_enums = { "status" => {} } } }

    def guarded(base)
      stub_const("ActiveRecord", Module.new)
      stub_const("ActiveRecord::Base", base)
      schemata(scan).overlay!
      base
    end

    it "drops a re-declared enum, by name or by values" do
      guarded(declared).enum(:status)
      declared.enum(status: { active: 0 })
      expect(declared.calls).to(be_empty)
    end

    it "passes a new enum through" do
      guarded(declared).enum(:role)
      expect(declared.calls).to(eq([[:role]]))
    end

    it "passes enum through when the model class has no defined_enums" do
      guarded(plain).enum(:status)
      expect(plain.calls).to(eq([[:status]]))
    end

    it "is installed only once per process" do
      ancestors = guarded(declared).singleton_class.ancestors.size
      guarded(declared)
      expect(declared.singleton_class.ancestors.size).to(eq(ancestors))
    end
  end

  # `normalizes` wraps the type in a decorator exposing +subtype+.
  describe "serialized attribute types" do
    before do
      stub_const("ActiveRecord", Module.new)
      stub_const("ActiveRecord::Type::Serialized", Class.new)
    end

    def serialized?(type) = Kimera::Execution::AttributeType.new(type).serialized?

    it "are found through cast_type wrapper chains" do
      wrapper = Struct.new(:cast_type)
      serialized = ActiveRecord::Type::Serialized.new
      types = [serialized, wrapper.new(serialized), wrapper.new(wrapper.new(serialized))]
      expect(types.map { |type| serialized?(type) }).to(eq([true, true, true]))
    end

    it "are not found in an empty wrapper, a plain object or nil" do
      types = [Struct.new(:cast_type).new(nil), Object.new, nil]
      expect(types.map { |type| serialized?(type) }).to(eq([false, false, false]))
    end

    it "are found through a subtype wrapper" do
      subtyped = Struct.new(:subtype)
      types = [subtyped.new(ActiveRecord::Type::Serialized.new), subtyped.new(Object.new)]
      expect(types.map { |type| serialized?(type) }).to(eq([true, false]))
    end
  end

  describe "callback overlay guard" do
    def fake_callback(kind, filter)
      Data.define(:kind, :filter).new(kind, filter)
    end

    # Stand-in for ActiveSupport::Callbacks::ClassMethods, fresh for each example.
    let(:callback_methods) do
      proc do
        def set_callback(name, *filters, &block)
          registered << [name, filters.dup, block]
        end
        private

        # Order matters: shift and pop mutate filters before the dup.
        def normalize_callback_params(filters, block)
          type = %i[before after around].include?(filters.first) ? filters.shift : :before
          options = filters.last.is_a?(Hash) ? filters.pop : {}
          values = filters.dup
          values << block if block
          [type, values, options]
        end

        def get_callbacks(_name) = chain
      end
    end
    let(:validator) do
      Class.new do
        attr_reader :attributes

        def initialize(attributes) = @attributes = attributes
      end
    end

    def callbacks
      fixture = Module.new(&callback_methods)
      stub_const("ActiveSupport", Module.new) unless defined?(ActiveSupport)
      stub_const("ActiveSupport::Callbacks", Module.new)
      stub_const("ActiveSupport::Callbacks::ClassMethods", fixture)
      fixture
    end

    def fake_model(chain)
      fixture = callbacks
      Class.new do
        class << self
          attr_accessor :chain

          def registered = @_registered ||= []
        end
      end.tap do |klass|
        klass.extend(fixture)
        klass.chain = chain
      end
    end

    # Same file:line, as a re-run class body makes. The guard matches by file
    # because synthesis shifts line numbers.
    def procs
      Array.new(2) { -> { :cb } }
    end

    def elsewhere = RubyVM::InstructionSequence.compile("-> { :other }", "some/other_model.rb").eval

    it "drops a proc filter re-registered from the same source location during overlay" do
      original, redeclared = procs
      klass = fake_model([fake_callback(:after, original)])
      overlaying { klass.set_callback(:commit, :after, redeclared) }
      expect(klass.registered).to(be_empty)
    end

    it "registers a proc from a different file during overlay" do
      fresh = -> { :fresh }
      klass = fake_model([fake_callback(:after, elsewhere)])
      overlaying { klass.set_callback(:commit, :after, fresh) }
      expect(klass.registered).to(eq([[:commit, [:after, fresh, {}], nil]]))
    end

    # A re-run drops the validator it re-mints; one with new attributes is kept.
    it "drops a re-minted validator-style object filter during overlay" do
      klass = fake_model([fake_callback(:before, validator.new([:title]))])
      filters = [[:title], [:description]].map { |attributes| validator.new(attributes) }
      overlaying { filters.each { |filter| klass.set_callback(:validate, :before, filter) } }
      expect(klass.registered.map { |entry| entry[1][1].attributes }).to(eq([[:description]]))
    end

    it "drops an already-chained symbol filter and keeps a new one during overlay" do
      klass = fake_model([fake_callback(:before, :old_hook)])
      overlaying { klass.set_callback(:save, :before, :old_hook, :new_hook) }
      expect(klass.registered).to(eq([[:save, [:before, :new_hook, {}], nil]]))
    end

    it "leaves registration untouched outside overlay even with the guard installed" do
      original, redeclared = procs
      klass = fake_model([fake_callback(:after, original)])
      Kimera::Execution::OverlayGuards.new.install!
      klass.set_callback(:commit, :after, redeclared)
      expect(klass.registered).to(eq([[:commit, [:after, redeclared], nil]]))
    end

    it "installs the callback guard only once per process" do
      fixture = callbacks
      bare = fixture.ancestors
      2.times { Kimera::Execution::OverlayGuards.new.install! }
      expect(fixture.ancestors - bare).to(eq([Kimera::Execution::GuardModules::CALLBACKGUARD]))
    end

    it "only dedupes against callbacks of the same kind" do
      original, redeclared = procs
      klass = fake_model([fake_callback(:before, original)])
      overlaying { klass.set_callback(:commit, :after, redeclared) }
      expect(klass.registered).to(eq([[:commit, [:after, redeclared, {}], nil]]))
    end

    it "clears the overlaying flag even when the overlay raises", :aggregate_failures do
      callbacks
      expect { overlaying { raise(RuntimeError, "boom") } }.to(raise_error("boom"))
      expect(Kimera::RUNTIME).not_to(be_overlaying)
    end
  end

  describe "serialize overlay guard" do
    def records(type = nil, &)
      stub_const("ActiveRecord", Module.new)
      stub_const("ActiveRecord::Type", Module.new)
      stub_const("ActiveRecord::Type::Serialized", Class.new)
      type ||= yield
      base =
        Class.new do
          class << self
            def calls = @_calls ||= []
            def serialize(attribute, *_arguments, **_options) = calls << attribute
          end
        end
      stub_const("ActiveRecord::Base", base)
      klass = Class.new(base)
      klass.define_singleton_method(:type_for_attribute) { |_n| type }
      Kimera::Execution::OverlayGuards.new.install!
      klass
    end

    it "drops a re-run serialize for an already-serialized attribute during overlay" do
      wrapper = Struct.new(:cast_type)
      klass = records { wrapper.new(ActiveRecord::Type::Serialized.new) }

      Kimera::Execution::OverlayGuards.new.overlay { klass.serialize(:actions, coder: JSON) }

      expect(klass.calls).to(be_empty)
    end

    it "passes serialize through for a plain attribute, and always outside overlay" do
      klass = records(Object.new)

      Kimera::Execution::OverlayGuards.new.overlay { klass.serialize(:actions, coder: JSON) }
      klass.serialize(:actions, coder: JSON)

      expect(klass.calls).to(eq(%i[actions actions]))
    end
  end

  # Mimics a class_attribute: a subclass reads its parent's value until it writes its own.
  def reflective
    own = {}
    Module.new do
      define_method(:_reflections) do
        own.fetch(self) { superclass.respond_to?(:_reflections) ? superclass._reflections : {} }
      end
      define_method(:_reflections=) { |value| own[self] = value }
    end.include(clearing)
  end

  # Counts each class's reflection-cache clears, and finds its subclasses.
  def clearing
    cleared = Hash.new(0)
    Module.new do
      define_method(:cleared) { cleared[self] }
      define_method(:clear_reflections_cache) { cleared[self] += 1 }
      define_method(:descendants) { ObjectSpace.each_object(Class).select { |k| k < self } }
    end
  end

  describe "reflection overlay guard" do
    # Mimics ActiveRecord::Reflection.add_reflection, which moves a redeclared
    # name to the end, and class_attribute copies.
    def adding(normal)
      Module.new.tap do |reflection|
        reflection.define_singleton_method(:add_reflection) do |owner, name, value|
          named = name.public_send(normal)
          owner._reflections = owner._reflections.except(named).merge!(named => value)
        end
      end
    end

    def records(key)
      reflection = adding(key.is_a?(String) ? :to_s : :to_sym)
      stub_const("ActiveRecord", Module.new)
      stub_const("ActiveRecord::Reflection", reflection)
      Kimera::Execution::OverlayGuards.new.install!
      base = Class.new.extend(reflective)
      reflection.add_reflection(base, key, :old)
      [reflection, base]
    end

    def heirs(base, key)
      own = Class.new(base)
      own._reflections = base._reflections.merge(other: :x)
      redeclared = Class.new(base)
      redeclared._reflections = base._reflections.merge(key => :theirs)
      [own, Class.new(base), redeclared]
    end

    # The base, then a subclass with its own copy, one sharing the base's, and one redeclaring the reflection.
    def overlaid_heirs
      reflection, base = records(:primary)
      [base, *heirs(base, :primary)].tap do
        overlaying { reflection.add_reflection(base, "primary", :new) }
      end
    end

    it "hands an overlaid reflection to subclasses holding a stale private copy" do
      expect(overlaid_heirs.map { |k| k._reflections[:primary] }).to(eq(%i[new new new theirs]))
    end

    it "keeps the rest of a subclass's private copy" do
      expect(overlaid_heirs[1]._reflections[:other]).to(eq(:x))
    end

    it "clears the reflection cache of the subclasses it hands the reflection to" do
      _, own, _, redeclared = overlaid_heirs
      expect([own.cleared, redeclared.cleared]).to(eq([1, 0]))
    end

    it "matches string-keyed reflections (Rails 7)" do
      reflection, base = records("primary")
      own, = heirs(base, "primary")
      Kimera::Execution::OverlayGuards.new.overlay { reflection.add_reflection(base, :primary, :new) }
      expect(own._reflections["primary"]).to(eq(:new))
    end

    # once-campfire: `has_many :memberships do ... end` carries mutants, so the
    # overlay redeclares it after `has_many :users, through: :memberships`, and
    # Rails raised HasManyThroughOrderError for every Room.
    it "keeps a redeclared reflection where it was declared", :aggregate_failures do
      reflection, base = records("memberships")
      reflection.add_reflection(base, "users", :through)
      Kimera::Execution::OverlayGuards.new.overlay { reflection.add_reflection(base, "memberships", :new) }
      expect(base._reflections).to(eq("memberships" => :new, "users" => :through))
      expect(base._reflections.keys).to(eq(%w[memberships users]))
    end

    it "leaves subclasses alone outside overlay and for a first declaration" do
      reflection, base = records(:primary)
      own, = heirs(base, :primary)
      reflection.add_reflection(base, :primary, :new)
      overlaying { reflection.add_reflection(base, :fresh, :f) }
      expect(own._reflections.slice(:primary, :fresh)).to(eq(primary: :old))
    end
  end

  describe "concern overlay guard" do
    let(:mutated) do
      proc do
        scope :expired, :mutated
        scope :before, :mutated
        scope :fresh, :mutated
        has_many :notes
      end
    end

    # Ivar names must match ActiveSupport::Concern and the production guard.
    def test_concern
      concern =
        Module.new do
          def included(base = nil, &block)
            if base.nil?
              raise(RuntimeError, "MultipleIncludedBlocks") if instance_variable_defined?(:@_included_block)
              instance_variable_set(:@_included_block, block)
            else
              super
            end
          end

          def prepended(base = nil, &block)
            if base.nil?
              raise(RuntimeError, "MultiplePrependBlocks") if instance_variable_defined?(:@_prepended_block)
              instance_variable_set(:@_prepended_block, block)
            else
              super
            end
          end
        end
      stub_const("ActiveSupport", Module.new) unless defined?(ActiveSupport)
      stub_const("ActiveSupport::Concern", concern)
      Kimera::Execution::OverlayGuards.new.install!
      concern
    end

    def fresh_concern = Module.new.tap { |concern| concern.extend(test_concern) }

    # The classes the overlaid block re-runs on.
    def reruns(concern, hook = :included)
      [].tap { |ran| overlaying { concern.public_send(hook) { ran << self } } }
    end

    it "accepts an overlaid included block instead of raising" do
      concern = fresh_concern.tap { |m| m.included { :original } }
      expect { overlaying { concern.included { :overlaid } } }.not_to(raise_error)
    end

    def chained(ran)
      fresh_concern.tap do |concern|
        concern.included { ran << [:original, self] }
        overlaying { concern.included { |base| ran << [:overlaid, base] } }
      end
    end

    # The overlaid block is trimmed to its mutated statements, so a class that
    # includes the concern later needs the original block to run first.
    it "chains the overlaid included block after the original" do
      ran = []
      later = Class.new
      later.class_eval(&chained(ran).instance_variable_get(:@_included_block))
      expect(ran).to(eq([[:original, later], [:overlaid, later]]))
    end

    it "still raises on a genuine double included block outside overlay" do
      concern = fresh_concern.tap { |m| m.included { :original } }
      expect { concern.included { :again } }.to(raise_error("MultipleIncludedBlocks"))
    end

    it "replaces the prepended block during overlay" do
      concern = fresh_concern.tap { |m| m.prepended { :original } }
      expect { overlaying { concern.prepended { :overlaid } } }.not_to(raise_error)
    end

    it "still raises on a genuine double prepended block outside overlay" do
      concern = fresh_concern.tap { |m| m.prepended { :original } }
      expect { concern.prepended { :again } }.to(raise_error("MultiplePrependBlocks"))
    end

    %i[included prepended].each do |hook|
      it "stores a first-time #{hook} block even during overlay" do
        concern = fresh_concern
        overlaying { concern.public_send(hook) { :first } }
        expect(concern.instance_variable_get(:"@_#{hook}_block").call).to(eq(:first))
      end
    end

    # A scope declared in `included do` must reach classes that already ran
    # the old block, or its guarded lambda is never installed.
    it "re-runs an overlaid included block on each direct includer, not its subclasses" do
      concern = fresh_concern.tap { |m| m.included { :original } }
      includer = Class.new.tap { |k| k.include(concern) }
      outsiders = [Class.new(includer), Class.new]
      ran = reruns(concern)
      expect([ran, ran & outsiders]).to(eq([[includer], []]))
    end

    it "does not re-run a first-time block during overlay" do
      concern = fresh_concern
      Class.new.include(concern)
      expect(reruns(concern)).to(be_empty)
    end

    it "re-runs an overlaid prepended block on the classes that prepended it" do
      concern = fresh_concern.tap { |m| m.prepended { :original } }
      prepender = Class.new.tap { |k| k.prepend(concern) }
      expect(reruns(concern, :prepended)).to(eq([prepender]))
    end

    def invitation
      stub_const("SchemataSpace", Module.new)
      stub_const("SchemataExpiring", fresh_concern.tap { |m| m.included { :original } })
      load(File.join(dir, write("schemata_invitation.rb", <<~RUBY)))
        class SchemataSpace::Invitation
          def self.defined = @defined ||= {}
          def self.scope(name, body) = defined[name] = body
          def self.has_many(name, *) = defined[name] = :has_many
          def self.note(*) = nil
          note SchemataExpiring
          scope :before, :own
          include SchemataExpiring
          note :fresh
          scope :expired, :override
          has_many :notes
        end
      RUBY
      SchemataSpace::Invitation
    end

    # Rails keeps a scope the class redeclares after `include`; re-running the
    # concern's block must not clobber that override.
    it "skips a scope or association the includer redeclares after the include" do
      model = invitation
      overlaying { SchemataExpiring.included(&mutated) }
      expect(model.defined).to(eq(expired: :override, before: :mutated, notes: :has_many, fresh: :mutated))
    end

    it "installs the concern guard only once per process" do
      concern = test_concern
      2.times { Kimera::Execution::OverlayGuards.new.install! }
      expect(concern.ancestors.count(Kimera::Execution::GuardModules::CONCERNGUARD)).to(eq(1))
    end
  end

  describe "a file whose constant another overlaid file defines later" do
    def retried
      stub_const("SchemataLater", Module.new)
      write("sl_a_child.rb", "class SchemataLater::Child < SchemataLater::Parent\n  def gt(a, b) = a > b\nend\n")
      write("sl_b_parent.rb", "class SchemataLater::Parent\n  def lt(a, b) = a < b\nend\n")
      schemata(scan("sl_a_child.rb", "sl_b_parent.rb"))
    end

    it "is retried quietly" do
      loader = retried
      expect { loader.overlay! }.not_to(output.to_stderr)
    end

    it "is not skipped, and its class is defined" do
      loader = retried.tap(&:overlay!)
      expect([loader.skipped, SchemataLater::Child.new.gt(2, 1)]).to(eq([{}, true]))
    end
  end

  it "reports a constant that stays missing once, after the retry", :aggregate_failures do
    write("sl_orphan.rb", "class SchemataOrphan < SchemataNowhere\n  def gt(a, b) = a > b\nend\n")
    registry = Kimera::RegistryScan.new(root: dir).build([File.join(dir, "sl_orphan.rb")])

    loader = described_class.new(registry, root: dir)
    expect { loader.overlay! }.to(output(/\Akimera: sl_orphan\.rb cannot run[^\n]*NameError[^\n]*\n\z/).to_stderr)
    expect(loader.skipped.keys).to(eq(["sl_orphan.rb"]))
  end

  # The overlay evaluates each file again; a method a file loaded later
  # wrapped keeps its wrapper, whichever file sorts first.
  it "overlays files in the order they were loaded, keeping a later file's wrapper" do
    write("sl_wrap_order.rb", "class SchemataWrapped\n  def total(s)\n    s >= 10 ? s - 1 : s\n  end\nend\n")
    write("sl_a_wrap.rb", <<~RUBY)
      class SchemataWrapped
        alias_method :plain, :total

        def total(s)
          t = plain(s)
          t > 5 ? t * 2 : t
        end
      end
    RUBY
    files = %w[sl_wrap_order.rb sl_a_wrap.rb].each { |name| require(File.join(dir, name)) }
    expect(outcomes(overlaid(*files.sort).first, ">= => >") { SchemataWrapped.new.total(10) }).to(eq([18, 20]))
  end

  it "keeps a wrapper that a file it doesn't mutate defined after the overlaid one" do
    write("sl_kept_order.rb", "class SchemataKept\n  def total(s)\n    s >= 10 ? s - 1 : s\n  end\nend\n")
    write("sl_kept_wrap.rb", "class SchemataKept\n  alias_method :plain, :total\n  def total(s) = plain(s).succ\nend\n")
    files = %w[sl_kept_order.rb sl_kept_wrap.rb].each { |name| require(File.join(dir, name)) }
    expect(outcomes(overlaid(files.first).first, ">= => >") { SchemataKept.new.total(10) }).to(eq([10, 11]))
  end
end
