# frozen_string_literal: true

require "kimera/execution/shift"
require "kimera/frameworks/suite"

using PointFields

RSpec.describe(Kimera::Frameworks) do
  describe Kimera::Frameworks::RunOutcome do
    it "exposes passed? mirroring the passed field", :aggregate_failures do
      expect(described_class.new(passed: true, failed_ids: []).passed?).to(be(true))
      expect(described_class.new(passed: false, failed_ids: ["a"]).passed?).to(be(false))
    end
  end

  describe "RunOutcome#to_h" do
    it "prints whether it passed, the failed ids and their failures, which it keeps to itself", :aggregate_failures do
      failed = Kimera::Frameworks::RunOutcome.new(passed: false, failed_ids: ["a"], failures: { "a" => "boom" })
      expect(failed.to_h).to(eq("passed" => false, "failed_ids" => ["a"], "failures" => { "a" => "boom" }))
      expect(Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: []).to_h)
        .to(eq("passed" => true, "failed_ids" => [], "failures" => {}))
      expect(failed.public_methods.intersect?(Kimera::Frameworks::RunOutcome.members)).to(be(false))
      expect(failed.expired?).to(be(false))
    end
  end

  describe Kimera::Execution::Shift::Expiry do
    it "prints a failed run of its test, whose message is the failure", :aggregate_failures do
      expiry = described_class.new(test: "t1", message: "ran past 2.0s")
      expect(expiry.to_h).to(eq("passed" => false, "failed_ids" => ["t1"], "failures" => { "t1" => "ran past 2.0s" }))
      expect([expiry.passed?, expiry.expired?]).to(eq([false, true]))
    end
  end

  describe "RunOutcome#verdict" do
    it "is survived when passed and killed with the failing ids otherwise", :aggregate_failures do
      expect(Kimera::Frameworks::RunOutcome.new(passed: true, failed_ids: []).verdict).to(eq([:survived, []]))
      expect(Kimera::Frameworks::RunOutcome.new(passed: false, failed_ids: ["a"]).verdict).to(eq([:killed, ["a"]]))
    end
  end

  describe "a test file that clashes with a dependency's constant" do
    def loaded(error)
      Kimera::Frameworks::Suite.new.__send__(:guarded, "test/x_test.rb") { raise(error) }
    rescue Kimera::Error => error
      error.message
    end

    before { require "prism" }

    it "names the constant and the gem that defines it", :aggregate_failures do
      message = loaded(TypeError.new("Prism is not a class"))
      hint = "Prism is a top-level constant that prism, a gem kimera runs on, defines in the process that " \
        "loads your suite, so the project's own Prism cannot load beside it: put the project's Prism in a namespace"
      expect(message).to(start_with("cannot load test file test/x_test.rb (TypeError: Prism is not a class)\n"))
      expect(message).to(end_with(hint))
    end

    it "adds nothing for a clash with a constant of the project's own", :aggregate_failures do
      stub_const("KimeraOwnWidget", Module.new)
      expect(loaded(TypeError.new("KimeraOwnWidget is not a class"))).not_to(include("\n"))
      expect(loaded(TypeError.new("String is not a module"))).not_to(include("\n"))
    end

    it "adds nothing for any other error" do
      plain = "cannot load test file test/x_test.rb (NameError: Prism is not a class)"
      expect(loaded(NameError.new("Prism is not a class"))).to(eq(plain))
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
      expect(adapter[*%w[b ghost a]].to_s).to(eq("rspec b a --order defined"))
    end

    it "describes an id as itself by default" do
      expect(described_class.new["Foo#bar"].name).to(eq("Foo#bar"))
    end

    it "knows no test's file by default" do
      expect(described_class.new["Foo#bar"].file).to(eq(""))
    end

    it "names the first of the tests it selects, and catalogs the known ones by name", :aggregate_failures do
      adapter = Class.new(described_class) { def test_ids = %w[a b] }.new
      expect([adapter["b", "a"].name, adapter[].name]).to(eq(["b", nil]))
      expect(adapter["b", "ghost", "a"].to_h).to(eq("b" => { "name" => "b" }, "a" => { "name" => "a" }))
    end

    it "has no plain rerun by default, so names no test failing in one", :aggregate_failures do
      selection = described_class.new["Foo#bar"]
      expect([selection.plain("/out.json"), selection.failed("Foo#bar failed", "/out.json")]).to(eq([[], []]))
    end

    it "has no hooks by default", :aggregate_failures do
      hooks = described_class.new.hooks
      expect([hooks.start, hooks.finish]).to(eq([nil, nil]))
    end
  end

  describe Kimera::Frameworks::SuiteRegistry do
    it "builds the suite its loader answers, by name (string or symbol)", :aggregate_failures do
      klass = Class.new(Kimera::Frameworks::Suite) { def self.build = :built }
      registry = described_class.new("demo" => -> { klass })
      expect(registry.load("demo")).to(eq(:built))
      expect(registry.load(:demo)).to(eq(:built))
    end

    def fresh(name)
      lib = File.expand_path("../../lib", __dir__)
      script = "require 'kimera/frameworks/suite'; " \
        "Kimera::Frameworks::SuiteRegistry.new.load(:#{name}).then { exit(0) }"
      system("ruby", "-I#{lib}", "-e", script, out: File::NULL, err: File::NULL)
    end

    it "loads a built-in adapter, here and in a fresh Ruby process", :aggregate_failures do
      expect(%i[rspec minitest].map { |name| described_class.new.load(name).class })
        .to(eq([Kimera::Frameworks::RSpecSuite, Kimera::Frameworks::MinitestSuite]))
      expect(%i[rspec minitest].map { |name| fresh(name) }).to(eq([true, true]))
    end

    it "turns a framework missing from the bundle into a Kimera::Error that names the fix" do
      missing = described_class.new("rspec" => -> { raise(LoadError, "cannot load such file -- rspec/core") })
      expect { missing.load(:rspec) }
        .to(raise_error(Kimera::Error, %r{framework rspec .* rspec/core.*set framework: rspec or minitest}))
    end

    it "raises a Kimera::Error for an unknown adapter name" do
      expect { described_class.new.load(:nonesuch) }
        .to(raise_error(Kimera::Error, /unknown test framework adapter: nonesuch/))
    end
  end
end
