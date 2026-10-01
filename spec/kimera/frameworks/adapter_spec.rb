# frozen_string_literal: true

require "kimera/frameworks/adapter"

RSpec.describe(Kimera::Frameworks) do
  describe Kimera::Frameworks::RunOutcome do
    it "exposes passed? mirroring the passed field", :aggregate_failures do
      expect(described_class.new(passed: true, failed_ids: []).passed?).to(be(true))
      expect(described_class.new(passed: false, failed_ids: ["a"]).passed?).to(be(false))
    end
  end

  describe "RunOutcome#verdict" do
    it "is survived when passed and killed with the failing ids otherwise", :aggregate_failures do
      expect(Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: []).verdict).to(eq([:survived, []]))
      expect(Kimera::Frameworks::RunOutcome.new(passed: false, failed_ids: ["a"]).verdict).to(eq([:killed, ["a"]]))
    end
  end

  describe Kimera::Frameworks::Adapter do
    it "raises NotImplementedError for the abstract methods", :aggregate_failures do
      adapter = described_class.new
      expect { adapter.source([]) }.to(raise_error(NotImplementedError))
      expect { adapter.test_ids }.to(raise_error(NotImplementedError))
      expect { adapter.run([]) }.to(raise_error(NotImplementedError))
    end

    it "reproduces the known failing ids with rspec in defined order" do
      adapter = Class.new(described_class) { def test_ids = %w[a b] }.new
      expect(adapter.reproduce(%w[b ghost a])).to(eq("rspec b a --order defined"))
    end

    it "describes an id as itself by default" do
      expect(described_class.new.describe("Foo#bar")).to(eq("Foo#bar"))
    end
  end

  describe Kimera::Frameworks::AdapterRegistry do
    it "registers and fetches an adapter by name (string or symbol)", :aggregate_failures do
      registry = described_class.new
      klass = Class.new(Kimera::Frameworks::Adapter)
      registry.register(:demo, klass)
      expect(registry.fetch("demo")).to(eq(klass))
      expect(registry.fetch(:demo)).to(eq(klass))
    end

    it "constructs a registered extension without a built-in loader" do
      registry = described_class.new
      instance = Object.new
      klass = Class.new(Kimera::Frameworks::Adapter)
      allow(klass).to(receive(:build).and_return(instance))
      registry.register(:demo, klass)
      expect(registry.load(:demo)).to(equal(instance))
    end

    it "loads a built-in adapter in a fresh Ruby process", :aggregate_failures do
      lib = File.expand_path("../../../lib", __dir__)
      script = 'require "kimera/frameworks/adapter"; Kimera::Frameworks::ADAPTERS.load(:rspec)'
      expect(Kimera::Frameworks::ADAPTERS.load(:rspec)).to(be_a(Kimera::Frameworks::RSpecAdapter))
      expect(system("ruby", "-I#{lib}", "-e", script, out: File::NULL, err: File::NULL)).to(be(true))
    end

    it "turns a framework missing from the bundle into a Kimera::Error that names the fix" do
      loader = described_class::LOADERS.fetch("rspec")
      allow(loader).to(receive(:call).and_raise(LoadError, "cannot load such file -- rspec/core"))
      expect { Kimera::Frameworks::ADAPTERS.load(:rspec) }
        .to(raise_error(Kimera::Error, %r{framework rspec .* rspec/core.*set framework: rspec or minitest}))
    end

    it "raises a Kimera::Error for an unknown adapter name" do
      expect { described_class.new.fetch(:nonesuch) }
        .to(raise_error(Kimera::Error, /unknown test framework adapter: nonesuch/))
    end
  end
end
