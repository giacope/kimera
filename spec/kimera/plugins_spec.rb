# frozen_string_literal: true

require "tmpdir"

require "kimera/plugins"

require_relative "../../examples/operators/kimera_plugin"

# The example plugin registers on load; reset so each example starts from the built-ins.
Kimera::Operators.reset!

RSpec.describe(Kimera::Plugins) do
  after { Kimera::Operators.reset! }

  def plugin(dir, body)
    File.join(dir, "plugin.rb").tap { |path| File.write(path, body) }
  end

  describe ".load!" do
    it "loads a plugin relative to the source root and returns what it registered" do
      Dir.mktmpdir do |dir|
        plugin(dir, <<~RUBY)
          class Sentinel < Kimera::Operators::Base
            def self.key = "sentinel"
            def variants(_node, **) = nil
          end
          Kimera::Operators.register(Sentinel)
        RUBY
        expect(described_class.load!(["plugin.rb"], root: dir).map(&:key)).to(eq(["sentinel"]))
      end
    end

    it "raises a usage error naming a plugin that does not exist" do
      Dir.mktmpdir do |dir|
        expect { described_class.load!(["nope.rb"], root: dir) }
          .to(raise_error(Kimera::UsageError, /cannot load nope\.rb: LoadError: cannot load such file/))
      end
    end

    it "raises a usage error carrying the parse error from a broken plugin" do
      Dir.mktmpdir do |dir|
        path = plugin(dir, "def broken(")
        expect { described_class.load!([path], root: dir) }
          .to(raise_error(Kimera::UsageError, /cannot load .*plugin\.rb: SyntaxError: .+/))
      end
    end

    it "lets a usage error raised by the plugin itself through untouched" do
      Dir.mktmpdir do |dir|
        path = plugin(dir, "Kimera::Operators.register(Object)")
        expect { described_class.load!([path], root: dir) }
          .to(raise_error(Kimera::UsageError, "not an operator class: Object"))
      end
    end

    it "does nothing when no plugins are configured" do
      expect(described_class.load!(nil)).to(eq([]))
    end
  end

  describe "the shipped example plugin" do
    before { Kimera::Operators.register(MyApp::Operators::ALL) }

    let(:keys) do
      %w[
        authorization background_dispatch bang_call cache_expiry
        encrypted_attribute http_status money_rounding
      ]
    end

    it "registers one operator per example file" do
      expect(Kimera::Operators.custom.map(&:key)).to(match_array(keys))
    end

    it "builds host operators alongside the built-ins under 'custom'" do
      built = Kimera::Operators.build(keys: %w[comparison custom])
      expect(built.map(&:key)).to(include("comparison", "authorization", "money_rounding"))
    end

    it "includes host operators in 'all'" do
      expect(Kimera::Operators.build(keys: ["all"]).map(&:key)).to(include("http_status"))
    end

    it "refuses a second operator claiming a registered key" do
      expect { Kimera::Operators.register(MyApp::Operators::Authorization) }
        .to(raise_error(Kimera::UsageError, /operator key already registered: authorization/))
    end

    it "refuses anything that is not an operator class, naming what it was handed" do
      error = "not an operator class: Object"
      expect { Kimera::Operators.register(Object) }.to(raise_error(Kimera::UsageError, error))
    end

    it "refuses the abstract base class itself" do
      expect { Kimera::Operators.register(Kimera::Operators::Base) }
        .to(raise_error(Kimera::UsageError, /not an operator class: Kimera::Operators::Base/))
    end
  end
end
