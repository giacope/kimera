# frozen_string_literal: true

require "fileutils"
require "kimera/execution/schemata"
require "kimera/registry/builder"
require "tmpdir"

RSpec.describe(Kimera::Execution::Schemata) do
  let(:dir) { Dir.mktmpdir }

  after do
    FileUtils.remove_entry(dir)
    Kimera::Runtime.reset!
  end

  def write(relative, body)
    path = File.join(dir, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, body)
    relative
  end

  it "overlays schema-safe files and returns the live mutant ids", :aggregate_failures do
    write("sl_target.rb", <<~RUBY)
      class SchemataTarget
        def gt(a, b)
          a > b
        end
      end
    RUBY
    registry = Kimera::RegistryScan.new(root: dir).build([File.join(dir, "sl_target.rb")])

    live = described_class.new(registry, root: dir).overlay!
    expect(live).to(match_array(registry.each.map { |m, _p| m.id }))

    object = SchemataTarget.new
    Kimera::Runtime.active = nil
    expect(object.gt(2, 1)).to(be(true))

    mutant = registry.each.find { |m, _p| m.label == "> => <" }.first
    Kimera::Runtime.active = mutant.id
    expect(object.gt(2, 1)).to(be(false))
  ensure
    Object.__send__(:remove_const, :SchemataTarget) if defined?(SchemataTarget)
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
  ensure
    Object.__send__(:remove_const, :SchemataMemo) if defined?(SchemataMemo)
  end

  it "never overlays a self-protected file", :aggregate_failures do
    relative = write("sl_protected.rb", <<~RUBY)
      class SchemataProtected
        def gt(a, b)
          a > b
        end
      end
    RUBY
    abs = File.join(dir, relative)
    # The builder checks protected? too, so stub after building.
    registry = Kimera::RegistryScan.new(root: dir).build([abs])
    allow(Kimera::SelfProtection).to(receive(:protected?).and_call_original)
    allow(Kimera::SelfProtection).to(receive(:protected?).with(abs).and_return(true))

    live = described_class.new(registry, root: dir).overlay!
    expect(live).to(eq([]))
    expect(defined?(SchemataProtected)).to(be_nil)
  ensure
    Object.__send__(:remove_const, :SchemataProtected) if defined?(SchemataProtected)
  end

  it "survives a top-level script that aborts when overlaid", :aggregate_failures do
    # Scripts may abort at top level when re-run. SystemExit is not a
    # StandardError, so uncaught it would kill the harness.
    write("sl_script.rb", <<~RUBY)
      abort("usage: nope") unless ARGV.include?("--never-there")

      def sl_script_helper(a, b)
        a > b
      end
    RUBY
    write("sl_after.rb", <<~RUBY)
      class SchemataAfter
        def gt(a, b)
          a > b
        end
      end
    RUBY
    files = [File.join(dir, "sl_script.rb"), File.join(dir, "sl_after.rb")]
    registry = Kimera::RegistryScan.new(root: dir).build(files)

    live = nil
    loader = described_class.new(registry, root: dir)
    # The abort's raw stderr must not leak; the diagnosis line carries it.
    expect { live = loader.overlay! }
      .to(output(/\Akimera: sl_script\.rb cannot run in warm workers.*\(SystemExit: usage: nope\)/).to_stderr)
    point = registry.points.find { |p| p.file == "sl_after.rb" }
    expect(live).to(include(*point.ids))
    # The reason lets callers tell unmutatable files from uncovered mutants.
    expect(loader.skipped).to(include("sl_script.rb" => "SystemExit: usage: nope"))
  ensure
    Object.__send__(:remove_const, :SchemataAfter) if defined?(SchemataAfter)
  end

  it "replays what a successful overlay wrote to stderr", :aggregate_failures do
    # $stderr.puts because evaluate silences Kernel#warn via $VERBOSE=nil.
    write("sl_warny.rb", <<~RUBY)
      class SchemataWarny
        $stderr.puts "sl_warny loading"

        def gt(a, b)
          a > b
        end
      end
    RUBY
    registry = Kimera::RegistryScan.new(root: dir).build([File.join(dir, "sl_warny.rb")])

    loader = described_class.new(registry, root: dir)
    expect { loader.overlay! }.to(output("sl_warny loading\n").to_stderr)
    expect(loader.skipped).to(be_empty)
  ensure
    Object.__send__(:remove_const, :SchemataWarny) if defined?(SchemataWarny)
  end

  it "skips a file whose synthesis raises and still overlays the rest", :aggregate_failures do
    # Unparser can raise on nodes it can't emit, such as `defined?`.
    write("sl_synth_bad.rb", <<~RUBY)
      class SchemataSynthBad
        def gt(a, b)
          a > b
        end
      end
    RUBY
    write("sl_synth_ok.rb", <<~RUBY)
      class SchemataSynthOk
        def gt(a, b)
          a > b
        end
      end
    RUBY
    files = [File.join(dir, "sl_synth_bad.rb"), File.join(dir, "sl_synth_ok.rb")]
    registry = Kimera::RegistryScan.new(root: dir).build(files)

    loader = described_class.new(registry, root: dir)
    synth = loader.__send__(:synth)
    allow(synth).to(receive(:synthesize).and_wrap_original) do |original, file, source|
      raise(Unparser::UnknownNodeError, "Unknown node type: :defined") if file == "sl_synth_bad.rb"

      original.call(file, source)
    end

    live = nil
    expect { live = loader.overlay! }
      .to(output(/sl_synth_bad\.rb cannot run in warm workers.*UnknownNodeError/).to_stderr)
    point = registry.points.find { |p| p.file == "sl_synth_ok.rb" }
    expect(live).to(include(*point.ids))
    expect(point).to(be_safe)
    bad = registry.points.select { |p| p.file == "sl_synth_bad.rb" }
    expect(bad.map(&:unsafe_reason).uniq)
      .to(eq(["unmutatable: schemata setup failed (Unparser::UnknownNodeError: Unknown node type: :defined)"]))
  ensure
    Object.__send__(:remove_const, :SchemataSynthOk) if defined?(SchemataSynthOk)
  end

  it "ignores registry files that no longer exist on disk", :aggregate_failures do
    registry = Kimera::RegistryScan.new(root: dir).source(
      "def m(a, b)\n  a > b\nend\n", file: "vanished.rb"
    )
    loader = described_class.new(registry, root: dir)
    live = nil
    # Absent is not unmutatable: no warning and no skipped entry.
    expect { live = loader.overlay! }.not_to(output.to_stderr)
    expect(live).to(eq([]))
    expect(loader.skipped).to(eq({}))
  end

  it "installs the enum overlay guard when ActiveRecord is present", :aggregate_failures do
    base =
      Class.new do
        def self.defined_enums = { "status" => {} }

        def self.enum(*args, **_kwargs) = (@calls ||= []) << args

        class << self
          attr_reader :calls
        end
      end
    stub_const("ActiveRecord", Module.new)
    stub_const("ActiveRecord::Base", base)

    registry = Kimera::RegistryScan.new(root: dir).build([])
    described_class.new(registry, root: dir).overlay!

    # The overlay re-runs class bodies, which re-declares defined enums.
    ActiveRecord::Base.enum(:status)
    expect(base.calls).to(be_nil)
    ActiveRecord::Base.enum(status: { active: 0 })
    expect(base.calls).to(be_nil)
    ActiveRecord::Base.enum(:role)
    expect(base.calls).to(eq([[:role]]))
  end

  it "installs the enum overlay guard only once per process" do
    base =
      Class.new do
        def self.defined_enums = {}
      end
    stub_const("ActiveRecord", Module.new)
    stub_const("ActiveRecord::Base", base)

    registry = Kimera::RegistryScan.new(root: dir).build([])
    described_class.new(registry, root: dir).overlay!
    ancestors = base.singleton_class.ancestors.size
    described_class.new(registry, root: dir).overlay!
    expect(base.singleton_class.ancestors.size).to(eq(ancestors))
  end

  it "passes enum through when the model class has no defined_enums" do
    base =
      Class.new do
        def self.enum(*args, **_kwargs) = (@calls ||= []) << args

        class << self
          attr_reader :calls
        end
      end
    stub_const("ActiveRecord", Module.new)
    stub_const("ActiveRecord::Base", base)

    registry = Kimera::RegistryScan.new(root: dir).build([])
    described_class.new(registry, root: dir).overlay!

    ActiveRecord::Base.enum(:status)
    expect(base.calls).to(eq([[:status]]))
  end

  describe "callback overlay guard" do
    def fake_callback(kind, filter)
      Data.define(:kind, :filter).new(kind, filter)
    end

    # Stand-in for ActiveSupport::Callbacks::ClassMethods.
    def callbacks
      fixture =
        Module.new do
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
      stub_const("ActiveSupport", Module.new) unless defined?(ActiveSupport)
      stub_const("ActiveSupport::Callbacks", Module.new)
      stub_const("ActiveSupport::Callbacks::ClassMethods", fixture)
      fixture
    end

    def fake_model(chain)
      Class.new do
        class << self
          attr_accessor :chain

          def registered = @_registered ||= []
        end
      end.tap do |klass|
        klass.extend(ActiveSupport::Callbacks::ClassMethods)
        klass.chain = chain
      end
    end

    # Same file:line, as a re-run class body makes. The guard matches by file
    # because synthesis shifts line numbers.
    def procs
      Array.new(2) { -> { :cb } }
    end

    it "drops a proc filter re-registered from the same source location during overlay" do
      callbacks
      original, redeclared = procs
      klass = fake_model([fake_callback(:after, original)])

      described_class.with_guards { klass.set_callback(:commit, :after, redeclared) }

      expect(klass.registered).to(be_empty)
    end

    it "registers a proc from a different file during overlay" do
      callbacks
      existing = eval("-> { :other }", binding, "some/other_model.rb")

      fresh = -> { :fresh }
      klass = fake_model([fake_callback(:after, existing)])

      described_class.with_guards { klass.set_callback(:commit, :after, fresh) }

      expect(klass.registered).to(eq([[:commit, [:after, fresh, {}], nil]]))
    end

    it "drops a re-minted validator-style object filter during overlay", :aggregate_failures do
      callbacks
      validator =
        Class.new do
          attr_reader :attributes

          def initialize(attributes) = @attributes = attributes
        end
      klass = fake_model([fake_callback(:before, validator.new([:title]))])

      described_class.with_guards do
        klass.set_callback(:validate, :before, validator.new([:title]))       # re-run: dropped
        klass.set_callback(:validate, :before, validator.new([:description])) # new attrs: kept
      end

      expect(klass.registered.size).to(eq(1))
      expect(klass.registered.first[1][1].attributes).to(eq([:description]))
    end

    it "drops an already-chained symbol filter and keeps a new one during overlay" do
      callbacks
      klass = fake_model([fake_callback(:before, :old_hook)])

      described_class.with_guards do
        klass.set_callback(:save, :before, :old_hook, :new_hook)
      end

      expect(klass.registered).to(eq([[:save, [:before, :new_hook, {}], nil]]))
    end

    it "leaves registration untouched outside overlay even with the guard installed" do
      callbacks
      original, redeclared = procs
      klass = fake_model([fake_callback(:after, original)])

      described_class.install!
      klass.set_callback(:commit, :after, redeclared)

      expect(klass.registered).to(eq([[:commit, [:after, redeclared], nil]]))
    end

    it "installs the callback guard only once per process", :aggregate_failures do
      fixture = callbacks
      described_class.install!
      ancestors = fixture.ancestors.size
      described_class.install!
      expect(fixture.ancestors.size).to(eq(ancestors))
      expect(fixture.ancestors).to(include(Kimera::Execution::OverlayGuardModules.callback))
    end

    it "only dedupes against callbacks of the same kind" do
      callbacks
      original, redeclared = procs
      klass = fake_model([fake_callback(:before, original)])

      described_class.with_guards { klass.set_callback(:commit, :after, redeclared) }

      expect(klass.registered).to(eq([[:commit, [:after, redeclared, {}], nil]]))
    end

    it "walks wrapper chains to find a serialized type", :aggregate_failures do
      stub_const("ActiveRecord", Module.new)
      serialized = stub_const("ActiveRecord::Type::Serialized", Class.new)
      wrapper = Struct.new(:cast_type)

      expect(Kimera::Execution::OverlayGuards.serialized?(serialized.new)).to(be(true))
      expect(Kimera::Execution::OverlayGuards.serialized?(wrapper.new(serialized.new))).to(be(true))
      expect(Kimera::Execution::OverlayGuards.serialized?(wrapper.new(wrapper.new(serialized.new)))).to(be(true))
      expect(Kimera::Execution::OverlayGuards.serialized?(wrapper.new(nil))).to(be(false))
      expect(Kimera::Execution::OverlayGuards.serialized?(Object.new)).to(be(false))
      expect(Kimera::Execution::OverlayGuards.serialized?(nil)).to(be(false))
    end

    # `normalizes` wraps the type in a decorator exposing +subtype+.
    it "walks a subtype wrapper chain too", :aggregate_failures do
      stub_const("ActiveRecord", Module.new)
      serialized = stub_const("ActiveRecord::Type::Serialized", Class.new)
      subtyped = Struct.new(:subtype)

      expect(Kimera::Execution::OverlayGuards.serialized?(subtyped.new(serialized.new))).to(be(true))
      expect(Kimera::Execution::OverlayGuards.serialized?(subtyped.new(Object.new))).to(be(false))
    end

    it "clears the overlaying flag even when the overlay raises", :aggregate_failures do
      callbacks
      expect do
        described_class.with_guards { raise(RuntimeError, "boom") }
      end.to(raise_error("boom"))
      expect(Kimera::Execution::OverlayGuards).not_to(be_overlaying)
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
            def serialize(attribute, *_args, **_options) = calls << attribute
          end
        end
      stub_const("ActiveRecord::Base", base)
      klass = Class.new(base)
      klass.define_singleton_method(:type_for_attribute) { |_n| type }
      described_class.install!
      klass
    end

    it "drops a re-run serialize for an already-serialized attribute during overlay" do
      wrapper = Struct.new(:cast_type)
      klass = records { wrapper.new(ActiveRecord::Type::Serialized.new) }

      described_class.with_guards { klass.serialize(:actions, coder: JSON) }

      expect(klass.calls).to(be_empty)
    end

    it "passes serialize through for a plain attribute, and always outside overlay" do
      klass = records(Object.new)

      described_class.with_guards { klass.serialize(:actions, coder: JSON) }
      klass.serialize(:actions, coder: JSON)

      expect(klass.calls).to(eq(%i[actions actions]))
    end
  end

  # Mimics a class_attribute: a subclass reads its parent's value until it writes its own.
  def reflective
    own = {}
    cleared = Hash.new(0)
    Module.new do
      define_method(:_reflections) do
        own.fetch(self) { superclass.respond_to?(:_reflections) ? superclass._reflections : {} }
      end
      define_method(:_reflections=) { |value| own[self] = value }
      define_method(:cleared) { cleared[self] }
      define_method(:clear_reflections_cache) { cleared[self] += 1 }
      define_method(:descendants) { ObjectSpace.each_object(Class).select { |k| k < self } }
    end
  end

  describe "reflection overlay guard" do
    # Mimics ActiveRecord::Reflection.add_reflection and class_attribute copies.
    def records(key)
      normal = key.is_a?(String) ? :to_s : :to_sym
      reflection = Module.new
      reflection.define_singleton_method(:add_reflection) do |owner, name, value|
        owner._reflections = owner._reflections.merge(name.public_send(normal) => value)
      end
      stub_const("ActiveRecord", Module.new)
      stub_const("ActiveRecord::Reflection", reflection)
      described_class.install!
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

    it "hands an overlaid reflection to subclasses holding a stale private copy", :aggregate_failures do
      reflection, base = records(:primary)
      own, shared, redeclared = heirs(base, :primary)
      described_class.with_guards { reflection.add_reflection(base, "primary", :new) }
      expect([base, own, shared, redeclared].map { |k| k._reflections[:primary] }).to(eq(%i[new new new theirs]))
      expect(own._reflections[:other]).to(eq(:x))
      expect([own.cleared, redeclared.cleared]).to(eq([1, 0]))
    end

    it "matches string-keyed reflections (Rails 7)" do
      reflection, base = records("primary")
      own, = heirs(base, "primary")
      described_class.with_guards { reflection.add_reflection(base, :primary, :new) }
      expect(own._reflections["primary"]).to(eq(:new))
    end

    it "leaves subclasses alone outside overlay and for a first declaration", :aggregate_failures do
      reflection, base = records(:primary)
      own, = heirs(base, :primary)
      reflection.add_reflection(base, :primary, :new)
      described_class.with_guards { reflection.add_reflection(base, :fresh, :f) }
      expect(own._reflections[:primary]).to(eq(:old))
      expect(own._reflections.key?(:fresh)).to(be(false))
    end
  end

  describe "concern overlay guard" do
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
      described_class.install!
      concern
    end

    it "replaces the included block during overlay instead of raising", :aggregate_failures do
      test_concern
      concern = Module.new.tap { |m| m.extend(ActiveSupport::Concern) }
      concern.included { :original }

      replacement = nil
      described_class.with_guards do
        expect { concern.included { replacement = :overlaid } }.not_to(raise_error)
      end

      concern.instance_variable_get(:@_included_block).call
      expect(replacement).to(eq(:overlaid))
    end

    it "still raises on a genuine double included block outside overlay" do
      test_concern
      concern = Module.new.tap { |m| m.extend(ActiveSupport::Concern) }
      concern.included { :original }
      expect { concern.included { :again } }.to(raise_error("MultipleIncludedBlocks"))
    end

    it "replaces the prepended block during overlay" do
      test_concern
      concern = Module.new.tap { |m| m.extend(ActiveSupport::Concern) }
      concern.prepended { :original }
      described_class.with_guards do
        expect { concern.prepended { :overlaid } }.not_to(raise_error)
      end
    end

    it "still raises on a genuine double prepended block outside overlay" do
      test_concern
      concern = Module.new.tap { |m| m.extend(ActiveSupport::Concern) }
      concern.prepended { :original }
      expect { concern.prepended { :again } }.to(raise_error("MultiplePrependBlocks"))
    end

    it "stores a first-time included/prepended block even during overlay", :aggregate_failures do
      test_concern
      concern = Module.new.tap { |m| m.extend(ActiveSupport::Concern) }
      described_class.with_guards do
        concern.included { :first }
        concern.prepended { :first }
      end
      expect(concern.instance_variable_get(:@_included_block).call).to(eq(:first))
      expect(concern.instance_variable_get(:@_prepended_block).call).to(eq(:first))
    end

    # A scope declared in `included do` must reach classes that already ran
    # the old block, or its guarded lambda is never installed.
    it "re-runs an overlaid included block on each direct includer, not its subclasses", :aggregate_failures do
      test_concern
      concern = Module.new.tap { |m| m.extend(ActiveSupport::Concern) }
      concern.included { :original }
      includer = Class.new.tap { |k| k.include(concern) }
      heir = Class.new(includer)
      outsider = Class.new
      ran = []
      described_class.with_guards { concern.included { ran << self } }
      expect(ran).to(eq([includer]))
      expect(ran).not_to(include(heir, outsider))
    end

    it "does not re-run a first-time block during overlay" do
      test_concern
      concern = Module.new.tap { |m| m.extend(ActiveSupport::Concern) }
      Class.new.include(concern)
      ran = []
      described_class.with_guards { concern.included { ran << self } }
      expect(ran).to(be_empty)
    end

    it "re-runs an overlaid prepended block on the classes that prepended it" do
      test_concern
      concern = Module.new.tap { |m| m.extend(ActiveSupport::Concern) }
      concern.prepended { :original }
      prepender = Class.new.tap { |k| k.prepend(concern) }
      ran = []
      described_class.with_guards { concern.prepended { ran << self } }
      expect(ran).to(eq([prepender]))
    end

    # Rails keeps a scope the class redeclares after `include`; re-running the
    # concern's block must not clobber that override.
    it "skips a scope or association the includer redeclares after the include", :aggregate_failures do
      test_concern
      concern = Module.new.tap { |m| m.extend(ActiveSupport::Concern) }
      stub_const("SchemataExpiring", concern)
      concern.included { :original }
      path = write("schemata_invitation.rb", <<~RUBY)
        class SchemataInvitation
          def self.defined = @defined ||= {}
          def self.scope(name, body) = defined[name] = body
          def self.has_many(name, *) = defined[name] = :has_many
          scope :before, :own
          include SchemataExpiring
          scope :expired, :override
          has_many :notes
        end
      RUBY
      load(File.join(dir, path))
      invitation = SchemataInvitation
      described_class.with_guards do
        concern.included do
          scope :expired, :mutated
          scope :before, :mutated
          scope :fresh, :mutated
          has_many :notes
        end
      end
      expect(invitation.defined).to(eq(expired: :override, before: :mutated, notes: :has_many, fresh: :mutated))
    ensure
      Object.__send__(:remove_const, :SchemataInvitation) if defined?(SchemataInvitation)
    end

    it "installs the concern guard only once per process", :aggregate_failures do
      concern = test_concern
      described_class.install!
      described_class.install!
      expect(concern.ancestors.count(Kimera::Execution::OverlayGuardModules.concern)).to(eq(1))
    end
  end

  it "retries a file whose constant another overlaid file defines later", :aggregate_failures do
    write("sl_a_child.rb", "class SchemataChild < SchemataParent\n  def gt(a, b) = a > b\nend\n")
    write("sl_b_parent.rb", "class SchemataParent\n  def lt(a, b) = a < b\nend\n")
    files = %w[sl_a_child.rb sl_b_parent.rb].map { |name| File.join(dir, name) }
    registry = Kimera::RegistryScan.new(root: dir).build(files)

    loader = described_class.new(registry, root: dir)
    expect { loader.overlay! }.not_to(output.to_stderr)
    expect(loader.skipped).to(be_empty)
    expect(SchemataChild.new.gt(2, 1)).to(be(true))
  ensure
    %i[SchemataChild SchemataParent].each { |name| Object.__send__(:remove_const, name) if Object.const_defined?(name) }
  end

  it "reports a constant that stays missing once, after the retry", :aggregate_failures do
    write("sl_orphan.rb", "class SchemataOrphan < SchemataNowhere\n  def gt(a, b) = a > b\nend\n")
    registry = Kimera::RegistryScan.new(root: dir).build([File.join(dir, "sl_orphan.rb")])

    loader = described_class.new(registry, root: dir)
    expect { loader.overlay! }.to(output(/\Akimera: sl_orphan\.rb cannot run[^\n]*NameError[^\n]*\n\z/).to_stderr)
    expect(loader.skipped.keys).to(eq(["sl_orphan.rb"]))
  end
end
