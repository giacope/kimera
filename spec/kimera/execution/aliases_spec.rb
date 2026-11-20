# frozen_string_literal: true

require "fileutils"
require "kimera/execution/aliases"
require "kimera/execution/overrides"
require "tmpdir"

RSpec.describe(Kimera::Execution::Aliases) do
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "pricing.rb").tap { |file| File.write(file, "") } }

  def inside
    yield
  ensure
    FileUtils.remove_entry(dir)
  end

  def define(mod, factor, file) = mod.module_eval(["def price(a) = a * ", factor].join, file)

  def declared(mod = Module.new, file = path) = mod.tap { define(mod, 2, file) }

  def overlay(mod, file = path) = define(mod, 3, file)

  def held(holder, name, method)
    Kimera::Execution::Overrides::Held.new(Kimera::Execution::Redefinition.new(holder, name), method, :public, nil)
  end

  def holder(origin, &) = Class.new { include origin }.tap { |klass| klass.class_eval(&) }

  def costing(origin = declared) = [origin, holder(origin) { alias_method :cost, :price }]

  def witnessing(aliases)
    aliases.follow do
      yield
      aliases.witness
    end
  end

  it "re-points an alias declared in another file at the redefined method", :aggregate_failures do
    inside do
      origin, aliased = costing
      expect(described_class.new([path]).follow { overlay(origin) && :done }).to(eq(:done))
      expect(aliased.new.cost(1)).to(eq(3))
    end
  end

  it "re-points again after a later redefinition, without looking anew", :aggregate_failures do
    inside do
      origin, aliased = costing
      expect(followed(origin).again { define(origin, 4, path) && :again }).to(eq(:again))
      expect(aliased.new.cost(1)).to(eq(4))
    end
  end

  def followed(origin) = described_class.new([path]).tap { |tracker| tracker.follow { overlay(origin) } }

  def stripped
    origin, aliased = costing.tap { |(declaring, _)| declaring.remove_method(:price) }
    [origin, aliased, followed(origin)]
  end

  it "follows no alias whose method is gone from its holder" do
    inside do
      origin, aliased, aliases = stripped
      definition = origin.instance_method(:price).tap { |found| aliases.witness([held(origin, :price, found)]) }
      expect([aliases.reaches?(definition), aliased.instance_method(:cost).original_name]).to(eq([false, :price]))
    end
  end

  def wrapped(origin) = define(origin, 5, File.join(dir, "memo.rb").tap { |file| File.write(file, "") })

  it "takes back a method another file wrapped only from a module its holder includes", :aggregate_failures do
    origin, aliased = costing.tap { |(declaring, _)| wrapped(declaring) }
    unrelated, overlaid = [declared, Module.new.tap { overlay(it) }].map { it.instance_method(:price) }
    aliases = described_class.new([path]).tap { |tracker| tracker.follow { aliased } }
    aliases.witness([held(unrelated.owner, :price, unrelated), held(origin, :price, overlaid)])
    expect([aliases.reaches?(unrelated), aliases.reaches?(overlaid)]).to(eq([false, true]))
  end

  describe "an alias's visibility" do
    let(:aliased) do
      origin = declared
      visibilities =
        holder(origin) do
          alias_method :shown, :price
          alias_method :kept, :price
          alias_method :hidden, :price
          protected :kept
          private :hidden
        end
      visibilities.tap { described_class.new([path]).follow { overlay(origin) } }
    end

    it "is kept", :aggregate_failures do
      inside do
        expect(aliased.public_method_defined?(:shown)).to(be(true))
        expect(aliased.protected_method_defined?(:kept)).to(be(true))
        expect(aliased.private_method_defined?(:hidden)).to(be(true))
      end
    end

    it "does not stop a private alias from reaching the redefined method" do
      inside do
        expect(Class.new(aliased) { def reach(amount) = hidden(amount) }.new.reach(1)).to(eq(3))
      end
    end
  end

  it "re-points an alias of a private method" do
    inside do
      origin, aliased = costing(declared.tap { |mod| mod.module_eval { private :price } })
      described_class.new([path]).follow { overlay(origin) }
      expect(Class.new(aliased) { def reach(amount) = cost(amount) }.new.reach(1)).to(eq(3))
    end
  end

  def chained(origin)
    holder(origin) do
      alias_method :plain, :price
      define_method(:price) { |a| plain(a) + 1 }
    end
  end

  it "follows the original past an override in the alias's own class" do
    inside do
      klass = chained(origin = declared)
      described_class.new([path]).follow { overlay(origin) }
      expect([klass.new.plain(1), klass.new.price(1)]).to(eq([3, 4]))
    end
  end

  def singleton = Class.new.tap { |klass| declared(klass.singleton_class).alias_method(:cost, :price) }

  it "re-points an alias on a singleton class" do
    inside do
      klass = singleton
      described_class.new([path]).follow { overlay(klass.singleton_class) }
      expect(klass.cost(1)).to(eq(3))
    end
  end

  def opened?(klass)
    ObjectSpace.each_object(Class).any? { |each| each.singleton_class? && each.attached_object.equal?(klass) }
  end

  it "opens no singleton class to look for an alias" do
    inside do
      klass = Class.new
      described_class.new([path]).follow { :looked }
      expect(opened?(klass)).to(be(false))
    end
  end

  def reclaim(origin, aliased)
    overlay(origin)
    aliased.define_method(:cost) { |_a| :mine }
  end

  it "leaves an alias the block itself redefined" do
    inside do
      origin, aliased = costing
      described_class.new([path]).follow { reclaim(origin, aliased) }
      expect(aliased.new.cost(1)).to(eq(:mine))
    end
  end

  def watched(added) = costing.each { |mod| mod.define_singleton_method(:method_added) { |name| added << name } }

  it "redefines nothing the block left alone" do
    inside do
      added = [].tap { |names| watched(names) }
      described_class.new([path]).follow { :untouched }
      expect(added).to(be_empty)
    end
  end

  it "leaves an alias of a method from a file it does not watch" do
    inside do
      origin, aliased = costing
      described_class.new([File.join(dir, "other.rb")]).follow { overlay(origin) }
      expect(aliased.new.cost(1)).to(eq(2))
    end
  end

  it "skips an alias whose original was redefined before it looked" do
    inside do
      origin, aliased = costing.tap { |(declaring, _)| overlay(declaring) }
      witnessing(described_class.new([path])) { define(origin, 4, path) }
      expect(aliased.new.cost(1)).to(eq(2))
    end
  end

  it "re-points an alias it tracks whether or not each file is witnessed" do
    inside do
      origin, aliased = costing
      witnessing(described_class.new([path])) { overlay(origin) }
      expect(aliased.new.cost(1)).to(eq(3))
    end
  end

  def linked
    FileUtils.mkdir_p(File.join(dir, "real"))
    File.symlink(File.join(dir, "real"), File.join(dir, "linked"))
    File.realpath(File.join(dir, "real", "pricing.rb").tap { |file| File.write(file, "") })
  end

  def symlinked
    real = linked
    [real, *costing(declared(Module.new, real))]
  end

  it "matches a file loaded through its real path when given a symlinked one" do
    inside do
      real, origin, aliased = symlinked
      described_class.new([File.join(dir, "linked", "pricing.rb")]).follow { overlay(origin, real) }
      expect(aliased.new.cost(1)).to(eq(3))
    end
  end

  it "accepts a file that does not exist" do
    inside do
      expect(described_class.new([File.join(dir, "missing.rb")]).follow { :ok }).to(eq(:ok))
    end
  end

  describe "an alias whose original another file wrapped" do
    let(:wrapper) { File.join(dir, "tax.rb").tap { |file| File.write(file, "") } }
    let!(:klass) do
      declared(Class.new).tap do |wrapped|
        wrapped.alias_method(:plain, :price)
        wrap(wrapped)
      end
    end
    let(:aliases) { described_class.new([path]) }

    def wrapping = "def price(a) = plain(a) + 1"

    def wrap(target) = target.class_eval(wrapping, wrapper)

    def rewrapped
      overlay(klass)
      klass.instance_method(:price).tap { wrap(klass) }
    end

    def held(name, method) = super(klass, name, method)

    it "follows the overlaid original it is handed" do
      inside do
        aliases.follow { aliases.witness([held(:price, rewrapped)]) }
        expect([klass.new.plain(1), klass.new.price(1)]).to(eq([3, 4]))
      end
    end

    it "says which overlaid original an alias it tracks now reaches", :aggregate_failures do
      inside do
        overlaid = nil
        aliases.follow { aliases.witness([held(:price, overlaid = rewrapped)]) }
        expect([aliases.reaches?(overlaid), aliases.reaches?(klass.instance_method(:price))]).to(eq([true, false]))
      end
    end

    def handed
      overlaid = rewrapped
      aliases.witness([held(:plain, klass.instance_method(:plain)), held(:price, overlaid)])
    end

    it "takes the overlaid original of its own name, not another one handed over with it" do
      inside do
        aliases.follow { handed }
        expect(klass.new.plain(1)).to(eq(3))
      end
    end

    def witnessed
      overlay(klass)
      aliases.witness
      wrap(klass)
    end

    it "follows the original it finds in its own file again" do
      inside do
        aliases.follow { witnessed }
        expect(klass.new.plain(1)).to(eq(3))
      end
    end

    it "leaves the alias alone when nothing hands it a new original" do
      inside do
        aliases.follow { aliases.witness }
        expect([klass.new.plain(1), klass.new.price(1)]).to(eq([2, 3]))
      end
    end
  end
end
