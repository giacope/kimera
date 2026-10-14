# frozen_string_literal: true

RSpec.describe Settings do
  describe "readers" do
    it "returns defaults" do
      settings = described_class.new
      expect(settings.timeout).to eq(30)
      expect(settings.label).to eq("app")
    end

    it "returns overrides given with symbol keys" do
      expect(described_class.new(retries: 7).retries).to eq(7)
    end

    it "raises NoMethodError for unknown keys" do
      expect { described_class.new.colour }.to raise_error(NoMethodError)
    end

    it "rejects arguments to a reader" do
      expect { described_class.new.send(:label, 1) }.to raise_error(ArgumentError, /expected 0/)
    end
  end

  describe "writers" do
    it "coerces integers" do
      settings = described_class.new
      settings.timeout = "45"
      expect(settings.timeout).to eq(45)
    end

    it "coerces booleans from words" do
      settings = described_class.new
      settings.verbose = "Yes"
      expect(settings.verbose).to be(true)
      settings.verbose = "nope"
      expect(settings.verbose).to be(false)
    end

    it "stores other values as given" do
      settings = described_class.new
      settings.label = :worker
      expect(settings.label).to eq(:worker)
    end

    it "fails on a non-numeric integer" do
      expect { described_class.new.retries = "many" }.to raise_error(ArgumentError)
    end
  end

  describe "predicates" do
    it "treats false, zero and empty as false" do
      expect(described_class.new.verbose?).to be(false)
      expect(described_class.new(retries: 0).retries?).to be(false)
      expect(described_class.new(label: "").label?).to be(false)
      expect(described_class.new(label: nil).label?).to be(false)
    end

    it "treats other values as true" do
      expect(described_class.new.retries?).to be(true)
      expect(described_class.new(label: "x").label?).to be(true)
    end
  end

  describe "toggles" do
    it "flips a flag and returns the new value" do
      settings = described_class.new
      expect(settings.toggle_verbose).to be(true)
      expect(settings.toggle_verbose).to be(false)
    end
  end

  describe "respond_to?" do
    it "answers for known keys in every form" do
      settings = described_class.new
      expect(settings).to respond_to(:retries, :retries=, :retries?, :toggle_retries)
    end

    it "answers false for unknown keys" do
      expect(described_class.new).not_to respond_to(:colour)
    end
  end

  describe ".materialize" do
    it "turns a ghost method into a real one shared by all instances" do
      described_class.new.label
      expect(described_class.method_defined?(:label)).to be(true)
      expect(described_class.materialized).to include(:label)
    end
  end

  it "lists keys in order" do
    expect(described_class.new(zone: "utc").keys).to eq(%w[label retries timeout verbose zone])
  end
end
