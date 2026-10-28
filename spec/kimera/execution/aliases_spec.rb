# frozen_string_literal: true

require "fileutils"
require "kimera/execution/aliases"
require "kimera/execution/overrides"
require "tmpdir"

RSpec.describe(Kimera::Execution::Aliases) do
  let(:dir) { Dir.mktmpdir }
  let(:path) { File.join(dir, "pricing.rb").tap { |file| File.write(file, "") } }

  after { FileUtils.remove_entry(dir) }

  # The method as its file declares it, as the overlay redefines it, and as
  # something else redefines it before the overlay.
  def define(mod, factor, file) = mod.module_eval(["def price(a) = a * ", factor].join, file)

  def declared(mod = Module.new, file = path) = mod.tap { define(mod, 2, file) }

  def overlay(mod, file = path) = define(mod, 3, file)

  def holder(origin, &) = Class.new { include origin }.tap { |klass| klass.class_eval(&) }

  # A module declaring price in the watched file, and a class that aliases it as cost.
  def costing(origin = declared) = [origin, holder(origin) { alias_method :cost, :price }]

  # Follows the block, then has the tracker look at its files.
  def witnessing(aliases)
    aliases.follow do
      yield
      aliases.witness
    end
  end

  it "re-points an alias declared in another file at the redefined method", :aggregate_failures do
    origin, aliased = costing
    expect(described_class.new([path]).follow { overlay(origin) && :done }).to(eq(:done))
    expect(aliased.new.cost(1)).to(eq(3))
  end

  it "re-points again after a later redefinition, without looking anew", :aggregate_failures do
    origin, aliased = costing
    aliases = described_class.new([path]).tap { |tracker| tracker.follow { overlay(origin) } }
    expect(aliases.again { define(origin, 4, path) && :again }).to(eq(:again))
    expect(aliased.new.cost(1)).to(eq(4))
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
      expect(aliased.public_method_defined?(:shown)).to(be(true))
      expect(aliased.protected_method_defined?(:kept)).to(be(true))
      expect(aliased.private_method_defined?(:hidden)).to(be(true))
    end

    it "does not stop a private alias from reaching the redefined method" do
      expect(aliased.new.__send__(:hidden, 1)).to(eq(3))
    end
  end

  it "re-points an alias of a private method" do
    origin, aliased = costing(declared.tap { |mod| mod.__send__(:private, :price) })
    described_class.new([path]).follow { overlay(origin) }
    expect(aliased.new.__send__(:cost, 1)).to(eq(3))
  end

  def chained(origin)
    holder(origin) do
      alias_method :plain, :price
      define_method(:price) { |a| plain(a) + 1 }
    end
  end

  it "follows the original past an override in the alias's own class" do
    origin = declared
    klass = chained(origin)
    described_class.new([path]).follow { overlay(origin) }
    expect([klass.new.plain(1), klass.new.price(1)]).to(eq([3, 4]))
  end

  it "re-points an alias on a singleton class" do
    klass = Class.new
    declared(klass.singleton_class).alias_method(:cost, :price)
    described_class.new([path]).follow { overlay(klass.singleton_class) }
    expect(klass.cost(1)).to(eq(3))
  end

  # The overlay, then the block's own definition of the alias.
  def reclaim(origin, aliased)
    overlay(origin)
    aliased.define_method(:cost) { |_a| :mine }
  end

  it "leaves an alias the block itself redefined" do
    origin, aliased = costing
    described_class.new([path]).follow { reclaim(origin, aliased) }
    expect(aliased.new.cost(1)).to(eq(:mine))
  end

  it "redefines nothing the block left alone" do
    added = []
    origin, aliased = costing
    [origin, aliased].each { |mod| mod.define_singleton_method(:method_added) { |name| added << name } }
    described_class.new([path]).follow { :untouched }
    expect(added).to(be_empty)
  end

  it "leaves an alias of a method from a file it does not watch" do
    origin, aliased = costing
    described_class.new([File.join(dir, "other.rb")]).follow { overlay(origin) }
    expect(aliased.new.cost(1)).to(eq(2))
  end

  it "skips an alias whose original was redefined before it looked" do
    origin, aliased = costing
    overlay(origin)
    witnessing(described_class.new([path])) { define(origin, 4, path) }
    expect(aliased.new.cost(1)).to(eq(2))
  end

  it "re-points an alias it tracks whether or not each file is witnessed" do
    origin, aliased = costing
    witnessing(described_class.new([path])) { overlay(origin) }
    expect(aliased.new.cost(1)).to(eq(3))
  end

  # The real path of pricing.rb, whose directory is also linked.
  def linked
    FileUtils.mkdir_p(File.join(dir, "real"))
    File.symlink(File.join(dir, "real"), File.join(dir, "linked"))
    File.realpath(File.join(dir, "real", "pricing.rb").tap { |file| File.write(file, "") })
  end

  it "matches a file loaded through its real path when given a symlinked one" do
    real = linked
    origin, aliased = costing(declared(Module.new, real))
    described_class.new([File.join(dir, "linked", "pricing.rb")]).follow { overlay(origin, real) }
    expect(aliased.new.cost(1)).to(eq(3))
  end

  it "accepts a file that does not exist" do
    expect(described_class.new([File.join(dir, "missing.rb")]).follow { :ok }).to(eq(:ok))
  end

  # A wrapper in another file took over the original's name before the
  # overlay; the overlay's version of the original reaches the alias.
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

    # The overlay's version of the original, then the wrapper again, as an overlay leaves them.
    def rewrapped
      overlay(klass)
      klass.instance_method(:price).tap { wrap(klass) }
    end

    def held(name, method) = Kimera::Execution::Overrides::Held.new(klass, name, method, :public, 1..1)

    it "follows the overlaid original it is handed" do
      aliases.follow { aliases.witness([held(:price, rewrapped)]) }
      expect([klass.new.plain(1), klass.new.price(1)]).to(eq([3, 4]))
    end

    # R6B4-M7: what no alias reaches, a wrapper holding the method it replaced
    # (a memoizer) keeps from the overlay; kimera judges those mutants again.
    it "says which overlaid original an alias it tracks now reaches", :aggregate_failures do
      overlaid = nil
      aliases.follow { aliases.witness([held(:price, overlaid = rewrapped)]) }
      expect([aliases.reaches?(overlaid), aliases.reaches?(klass.instance_method(:price))]).to(eq([true, false]))
    end

    it "takes the overlaid original of its own name, not another one handed over with it" do
      aliases.follow do
        overlaid = rewrapped
        aliases.witness([held(:plain, klass.instance_method(:plain)), held(:price, overlaid)])
      end
      expect(klass.new.plain(1)).to(eq(3))
    end

    # The overlay, witnessed, then the wrapper again.
    def witnessed
      overlay(klass)
      aliases.witness
      wrap(klass)
    end

    it "follows the original it finds in its own file again" do
      aliases.follow { witnessed }
      expect(klass.new.plain(1)).to(eq(3))
    end

    # Its own name now resolves to the wrapper, which must not become the alias.
    it "leaves the alias alone when nothing hands it a new original" do
      aliases.follow { aliases.witness }
      expect([klass.new.plain(1), klass.new.price(1)]).to(eq([2, 3]))
    end
  end
end
