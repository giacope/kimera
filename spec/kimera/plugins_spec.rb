# frozen_string_literal: true

require "tmpdir"

require "kimera/plugins"

require_relative "../../examples/operators/kimera_plugin"

Kimera::Operators::ROSTER.reset!

RSpec.describe(Kimera::Plugins) do
  def roster
    yield
  ensure
    Kimera::Operators::ROSTER.reset!
  end

  def plugged(&) = roster { Dir.mktmpdir(&) }

  def plugin(dir, body)
    File.join(dir, "plugin.rb").tap { |path| File.write(path, body) }
  end

  describe "#load!" do
    it "loads a plugin relative to the source root and returns what it registered" do
      plugged do |dir|
        plugin(dir, <<~RUBY)
          class Sentinel < Kimera::Operators::Base
            def key = "sentinel"
            def variants(_node, **) = nil
          end
          Kimera::Operators.register(Sentinel)
        RUBY
        expect(described_class.new(["plugin.rb"], root: dir).load!.map { it.new.key }).to(eq(["sentinel"]))
      end
    end

    it "raises a usage error naming a plugin that does not exist" do
      plugged do |dir|
        expect { described_class.new(["nope.rb"], root: dir).load! }
          .to(raise_error(Kimera::UsageError, /cannot load nope\.rb: LoadError: cannot load such file/))
      end
    end

    it "raises a usage error carrying the parse error from a broken plugin" do
      plugged do |dir|
        path = plugin(dir, "def broken(")
        expect { described_class.new([path], root: dir).load! }
          .to(raise_error(Kimera::UsageError, /cannot load .*plugin\.rb: SyntaxError: .+/))
      end
    end

    it "lets a usage error raised by the plugin itself through untouched" do
      plugged do |dir|
        path = plugin(dir, "Kimera::Operators.register(Object)")
        expect { described_class.new([path], root: dir).load! }
          .to(raise_error(Kimera::UsageError, "not an operator class: Object"))
      end
    end

    it "does nothing when no plugins are configured" do
      expect(described_class.new(nil).load!).to(eq([]))
    end
  end

  describe "the shipped example plugin" do
    let(:keys) do
      %w[
        authorization background_dispatch bang_call cache_expiry
        encrypted_attribute http_status money_rounding
      ]
    end

    def shipped
      roster do
        Kimera::Operators.register(MyApp::Operators::ALL)
        yield
      end
    end

    it "registers one operator per example file" do
      shipped do
        expect(Kimera::Operators::ROSTER.custom.map { it.new.key }).to(match_array(keys))
      end
    end

    it "builds host operators alongside the built-ins under 'custom'" do
      shipped do
        built = Kimera::Operators.build(keys: %w[comparison custom])
        expect(built.map(&:key)).to(include("comparison", "authorization", "money_rounding"))
      end
    end

    it "includes host operators in 'all'" do
      shipped do
        expect(Kimera::Operators.build(keys: ["all"]).map(&:key)).to(include("http_status"))
      end
    end

    it "refuses a second operator claiming a registered key" do
      shipped do
        expect { Kimera::Operators.register(MyApp::Operators::Authorization) }
          .to(raise_error(Kimera::UsageError, /operator key already registered: authorization/))
      end
    end

    it "refuses anything that is not an operator class, naming what it was handed" do
      shipped do
        error = "not an operator class: Object"
        expect { Kimera::Operators.register(Object) }.to(raise_error(Kimera::UsageError, error))
      end
    end

    it "refuses the abstract base class itself" do
      shipped do
        expect { Kimera::Operators.register(Kimera::Operators::Base) }
          .to(raise_error(Kimera::UsageError, /not an operator class: Kimera::Operators::Base/))
      end
    end
  end
end
