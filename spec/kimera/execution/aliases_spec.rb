# frozen_string_literal: true

require "fileutils"
require "kimera/execution/aliases"
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

  it "re-points an alias declared in another file at the redefined method", :aggregate_failures do
    origin = declared
    aliased = holder(origin) { alias_method :cost, :price }
    expect(described_class.new([path]).follow { overlay(origin) && :done }).to(eq(:done))
    expect(aliased.new.cost(1)).to(eq(3))
  end

  it "re-points again after a later redefinition, without looking anew", :aggregate_failures do
    origin = declared
    aliased = holder(origin) { alias_method :cost, :price }
    aliases = described_class.new([path])
    aliases.follow { overlay(origin) }
    expect(aliases.again { define(origin, 4, path) && :again }).to(eq(:again))
    expect(aliased.new.cost(1)).to(eq(4))
  end

  it "keeps each alias's visibility", :aggregate_failures do
    origin = declared
    aliased =
      holder(origin) do
        alias_method :shown, :price
        alias_method :kept, :price
        alias_method :hidden, :price
        protected :kept
        private :hidden
      end
    described_class.new([path]).follow { overlay(origin) }
    expect(aliased.public_method_defined?(:shown)).to(be(true))
    expect(aliased.protected_method_defined?(:kept)).to(be(true))
    expect(aliased.private_method_defined?(:hidden)).to(be(true))
    expect(aliased.new.__send__(:hidden, 1)).to(eq(3))
  end

  it "re-points an alias of a private method" do
    origin = declared.tap { |mod| mod.__send__(:private, :price) }
    aliased = holder(origin) { alias_method :cost, :price }
    described_class.new([path]).follow { overlay(origin) }
    expect(aliased.new.__send__(:cost, 1)).to(eq(3))
  end

  it "follows the original past an override in the alias's own class", :aggregate_failures do
    origin = declared
    chained =
      holder(origin) do
        alias_method :plain, :price
        define_method(:price) { |a| plain(a) + 1 }
      end
    described_class.new([path]).follow { overlay(origin) }
    expect(chained.new.plain(1)).to(eq(3))
    expect(chained.new.price(1)).to(eq(4))
  end

  it "re-points an alias on a singleton class" do
    klass = Class.new
    declared(klass.singleton_class).alias_method(:cost, :price)
    described_class.new([path]).follow { overlay(klass.singleton_class) }
    expect(klass.cost(1)).to(eq(3))
  end

  it "leaves an alias the block itself redefined" do
    origin = declared
    aliased = holder(origin) { alias_method :cost, :price }
    described_class.new([path]).follow do
      overlay(origin)
      aliased.define_method(:cost) { |_a| :mine }
    end
    expect(aliased.new.cost(1)).to(eq(:mine))
  end

  it "redefines nothing the block left alone" do
    added = []
    origin = declared
    aliased = holder(origin) { alias_method :cost, :price }
    [origin, aliased].each { |mod| mod.define_singleton_method(:method_added) { |name| added << name } }
    described_class.new([path]).follow { :untouched }
    expect(added).to(be_empty)
  end

  it "leaves an alias of a method from a file it does not watch" do
    origin = declared
    aliased = holder(origin) { alias_method :cost, :price }
    described_class.new([File.join(dir, "other.rb")]).follow { overlay(origin) }
    expect(aliased.new.cost(1)).to(eq(2))
  end

  it "skips an alias whose original was redefined before it looked" do
    origin = declared
    aliased = holder(origin) { alias_method :cost, :price }
    overlay(origin)
    described_class.new([path]).follow { define(origin, 4, path) }
    expect(aliased.new.cost(1)).to(eq(2))
  end

  it "matches a file loaded through its real path when given a symlinked one" do
    FileUtils.mkdir_p(File.join(dir, "real"))
    File.symlink(File.join(dir, "real"), File.join(dir, "linked"))
    real = File.join(dir, "real", "pricing.rb").tap { |file| File.write(file, "") }
    origin = declared(Module.new, File.realpath(real))
    aliased = holder(origin) { alias_method :cost, :price }
    described_class.new([File.join(dir, "linked", "pricing.rb")]).follow { overlay(origin, File.realpath(real)) }
    expect(aliased.new.cost(1)).to(eq(3))
  end

  it "accepts a file that does not exist" do
    expect(described_class.new([File.join(dir, "missing.rb")]).follow { :ok }).to(eq(:ok))
  end
end
