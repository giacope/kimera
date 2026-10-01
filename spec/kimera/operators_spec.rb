# frozen_string_literal: true

require "kimera/operators"

RSpec.describe(Kimera::Operators) do
  let(:all_keys) do
    %w[
      comparison boolean_connective boolean_literal statement_deletion
      arithmetic negation safe_navigation conditional
      numeric_literal string_literal collection_literal range
      method_unwrap return_value selector_swap regexp
      rails_permit rails_validation rails_callback
      rails_association element_drop argument_drop op_assign
      index_fetch kernel_coercion respond_to_guard symbol_literal
      default_argument chain_link_deletion
    ]
  end
  let(:default_keys) do
    %w[comparison boolean_connective boolean_literal statement_deletion negation conditional]
  end

  describe ".keys" do
    it "lists every operator's stable key" do
      expect(described_class.keys).to(match_array(all_keys))
    end
  end

  describe ".build" do
    let(:built) { described_class.build }

    it "instantiates the conservative core by default" do
      expect(built.map(&:key)).to(match_array(described_class::DEFAULT_KEYS))
    end

    it "instantiates only the default keys by default" do
      expect(built.map(&:key)).to(match_array(default_keys))
    end

    it "expands the single key 'all' to every family" do
      built = described_class.build(keys: ["all"])
      expect(built.map(&:key)).to(match_array(described_class.keys))
    end

    it "selects only the requested keys (strings or symbols)" do
      built = described_class.build(keys: [:comparison, "boolean_literal"])
      expect(built.map(&:key)).to(contain_exactly("comparison", "boolean_literal"))
    end

    it "raises a usage error naming any unknown keys" do
      unknown = ["nope", :comparison]
      pattern = /unknown operator\(s\): nope \(valid: all, rails, custom, comparison/
      expect { described_class.build(keys: unknown) }.to(raise_error(Kimera::UsageError, pattern))
    end
  end

  describe Kimera::Operators::Base do
    it "requires subclasses to define #key" do
      expect { described_class.new.key }.to(raise_error(NotImplementedError, /must define #key/))
    end

    it "is neither a statement nor a class-body operator unless a subclass says so" do
      expect(described_class.new).to(have_attributes(statement?: false, body?: false))
    end

    it "requires subclasses to define #variants" do
      klass = Class.new(described_class) { def key = "demo" }
      expect { klass.new.variants(nil, position: false) }.to(raise_error(NotImplementedError, /must define #variants/))
    end
  end
end
