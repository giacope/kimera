# frozen_string_literal: true

require "json"
require "kimera/cli"
require "kimera/cli/config_template"
require "kimera/report/formats"
require "kimera/scope/ignore_list"

# The schema documents .kimera.yml for editors and supplies the comments
# `kimera init` writes, so it must list exactly what Kimera reads.
RSpec.describe(Kimera::CLI::ConfigTemplate, :aggregate_failures) do
  let(:schema) { JSON.parse(File.read(described_class::PATH)) }
  let(:properties) { schema.fetch("properties") }

  it "describes every config key Kimera reads, and no other" do
    keys = Kimera::Config::SCALAR_KEYS + Kimera::Config::LIST_KEYS + ["ignore"]
    expect(properties.keys).to(match_array(keys))
    expect(schema.fetch("additionalProperties")).to(be(false))
  end

  it "describes every ignore anchor, and requires the file and the reason" do
    entry = properties.dig("ignore", "items")
    anchors = Kimera::IgnoreList::ANCHORS.keys.map(&:to_s)
    expect(entry.fetch("properties").keys).to(match_array(anchors + %w[file reason]))
    expect(entry.fetch("required")).to(eq(%w[file reason]))
  end

  it "offers exactly the output formats Kimera writes" do
    expect(properties.dig("format", "enum")).to(eq(Kimera::Report::Formats::NAMES))
  end

  it "gives every key a description for init's comments and editors' hovers" do
    expect(properties.values).to(all(include("description")))
  end

  it "ships with the gem" do
    expect(Gem::Specification.load(File.expand_path("../../../kimera.gemspec", __dir__)).files)
      .to(include("schema/kimera.schema.json"))
  end

  it "keeps a line of exactly 78 characters whole, so each comment fits in 80 columns" do
    wrap = ->(text) { described_class.new({}).__send__(:wrap, text) }
    expect(wrap.call("#{"a" * 76} b")).to(eq(["#{"a" * 76} b"]))
    expect(wrap.call("#{"a" * 76} bc")).to(eq(["a" * 76, "bc"]))
  end

  it "wraps each key's description into comment lines that fit" do
    text = described_class.new("timeout_factor" => 4.0).render
    note = "# Relative timeout: multiple of the test's baseline time (default: 10)."
    expect(text).to(include("\n#{note}\ntimeout_factor: 4.0\n"))
    long = described_class.new("fail_on_no_coverage" => true).render.lines.grep(/^# Gate: also/)
    expect(long.first.chomp.size).to(be <= 78)
  end
end
