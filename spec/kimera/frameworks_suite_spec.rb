# frozen_string_literal: true

require "kimera/frameworks/suite"

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

  # The suite loads in a process that already holds kimera's dependencies,
  # so a project constant one of them defines at top level cannot load.
  describe "a test file that clashes with a dependency's constant" do
    def loaded(error)
      Kimera::Frameworks::Suite.new.__send__(:load_test_file, "test/x_test.rb") { raise(error) }
    rescue Kimera::Error => error
      error.message
    end

    before { require "parser" }

    it "names the constant and the gem that defines it", :aggregate_failures do
      message = loaded(TypeError.new("Parser is not a class"))
      hint = "Parser is a top-level constant that parser, a gem kimera runs on, defines in the process that " \
        "loads your suite, so the project's own Parser cannot load beside it: put the project's Parser in a namespace"
      expect(message).to(start_with("cannot load test file test/x_test.rb (TypeError: Parser is not a class)\n"))
      expect(message).to(end_with(hint))
    end

    it "adds nothing for a clash with a constant of the project's own", :aggregate_failures do
      stub_const("KimeraOwnWidget", Module.new)
      expect(loaded(TypeError.new("KimeraOwnWidget is not a class"))).not_to(include("\n"))
      expect(loaded(TypeError.new("String is not a module"))).not_to(include("\n"))
    end

    it "adds nothing for any other error" do
      plain = "cannot load test file test/x_test.rb (NameError: Parser is not a class)"
      expect(loaded(NameError.new("Parser is not a class"))).to(eq(plain))
    end

    it "adds nothing for a constant no one defines" do
      expect(loaded(TypeError.new("KimeraNowhere is not a class"))).not_to(include("\n"))
    end
  end

  describe Kimera::Frameworks::Suite do
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

    it "knows no test's file by default" do
      expect(described_class.new.test_file("Foo#bar")).to(eq(""))
    end
  end

  describe Kimera::Frameworks::SuiteRegistry do
    it "registers and fetches an adapter by name (string or symbol)", :aggregate_failures do
      registry = described_class.new
      klass = Class.new(Kimera::Frameworks::Suite)
      registry.register(:demo, klass)
      expect(registry.fetch("demo")).to(eq(klass))
      expect(registry.fetch(:demo)).to(eq(klass))
    end

    it "constructs a registered extension without a built-in loader" do
      registry = described_class.new
      klass = Class.new(Kimera::Frameworks::Suite).tap { |suite| allow(suite).to(receive(:build).and_return(:built)) }
      registry.register(:demo, klass)
      expect(registry.load(:demo)).to(eq(:built))
    end

    it "loads a built-in adapter in a fresh Ruby process", :aggregate_failures do
      lib = File.expand_path("../../lib", __dir__)
      script = 'require "kimera/frameworks/suite"; Kimera::Frameworks::SUITES.load(:rspec)'
      expect(Kimera::Frameworks::SUITES.load(:rspec)).to(be_a(Kimera::Frameworks::RSpecSuite))
      expect(system("ruby", "-I#{lib}", "-e", script, out: File::NULL, err: File::NULL)).to(be(true))
    end

    it "turns a framework missing from the bundle into a Kimera::Error that names the fix" do
      loader = described_class::LOADERS.fetch("rspec")
      allow(loader).to(receive(:call).and_raise(LoadError, "cannot load such file -- rspec/core"))
      expect { Kimera::Frameworks::SUITES.load(:rspec) }
        .to(raise_error(Kimera::Error, %r{framework rspec .* rspec/core.*set framework: rspec or minitest}))
    end

    it "raises a Kimera::Error for an unknown adapter name" do
      expect { described_class.new.fetch(:nonesuch) }
        .to(raise_error(Kimera::Error, /unknown test framework adapter: nonesuch/))
    end
  end
end
