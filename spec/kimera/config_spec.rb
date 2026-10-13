# frozen_string_literal: true

require "kimera/scope/config"
require "tmpdir"

RSpec.describe(Kimera::Config) do
  def with_config(yaml)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".kimera.yml"), yaml)
      yield(described_class.root(root: dir))
    end
  end

  let(:normalized_yaml) do
    <<~YAML
      framework: minitest
      jobs: 4
      max_survivors: 0
      max_ignored: 3
      coverage: false
      fail_on_no_coverage: true
      paths: ["app/**/*.rb"]
      operators: [comparison, boolean_connective]
      exclude: ["app/legacy/**/*.rb"]
      ignore:
        - file: app/models/x.rb
          line: 10
          label: "> => >="
          reason: equivalent at the boundary
    YAML
  end

  let(:normalized_ignore) do
    [
      {
        file: "app/models/x.rb", line: 10,
        label: "> => >=",
        reason: "equivalent at the boundary"
      }
    ]
  end

  it "wraps a scalar value under a list key in an array" do
    with_config("paths: lib/core.rb\n") do |options|
      expect(options[:paths]).to(eq(["lib/core.rb"]))
    end
  end

  it "returns an empty hash when no config exists" do
    Dir.mktmpdir { |dir| expect(described_class.root(root: dir)).to(eq({})) }
  end

  it "normalizes the framework and jobs keys", :aggregate_failures do
    with_config(normalized_yaml) do |options|
      expect(options[:framework]).to(eq("minitest"))
      expect(options[:jobs]).to(eq(4))
    end
  end

  it "normalizes the survivor and ignored count keys", :aggregate_failures do
    with_config(normalized_yaml) do |options|
      expect(options[:max_survivors]).to(eq(0))
      expect(options[:max_ignored]).to(eq(3))
    end
  end

  it "normalizes boolean keys", :aggregate_failures do
    with_config(normalized_yaml) do |options|
      expect(options[:coverage]).to(be(false))
      expect(options[:fail_on_no_coverage]).to(be(true))
    end
  end

  it "normalizes list keys", :aggregate_failures do
    with_config(normalized_yaml) do |options|
      expect(options[:paths]).to(eq(["app/**/*.rb"]))
      expect(options[:operators]).to(eq(%w[comparison boolean_connective]))
      expect(options[:exclude]).to(eq(["app/legacy/**/*.rb"]))
    end
  end

  it "normalizes the ignore key" do
    with_config(normalized_yaml) do |options|
      expect(options[:ignore]).to(eq(normalized_ignore))
    end
  end

  def with_baseline
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".kimera-baseline.yml"), <<~YAML)
        ignore:
          - file: app/models/old.rb
            line: 4
            label: "== => !="
            reason: pre-adoption debt
      YAML
      File.write(File.join(dir, ".kimera.yml"), "baseline: .kimera-baseline.yml\n#{normalized_yaml.lines.last(5).join}")
      described_class.root(root: dir)
    end
  end

  def accepted = { file: "app/models/old.rb", line: 4, label: "== => !=", reason: "pre-adoption debt" }

  it "keeps a reasoned baseline file's entries apart from the local ignore entries", :aggregate_failures do
    options = with_baseline
    expect(options.fetch(:ignore)).to(eq(normalized_ignore))
    expect(options.fetch(:baseline_ignore)).to(eq([accepted]))
  end

  it "applies baseline entries after local ones unless --no-baseline cleared baseline", :aggregate_failures do
    options = with_baseline
    expect(described_class.ignores(options)).to(eq(normalized_ignore + [accepted]))
    expect(described_class.ignores(options.merge(baseline: false))).to(eq(normalized_ignore))
    expect(described_class.ignores({})).to(eq([]))
  end

  it "omits keys that are not present" do
    with_config("jobs: 2\n") do |options|
      expect(options).to(eq(jobs: 2))
    end
  end

  it "rejects an ignore entry without a reason" do
    yaml = <<~YAML
      ignore:
        - file: app/models/x.rb
          label: "> => >="
    YAML
    expect { with_config(yaml) }.to(raise_error(Kimera::UsageError, /needs a reason/))
  end

  it "rejects an ignore entry without a file" do
    yaml = <<~YAML
      ignore:
        - label: "> => >="
          reason: because
    YAML
    # The message names the rule, so the user can find it among several.
    expect { with_config(yaml) }.to(raise_error(Kimera::UsageError, /missing file: .+label.+because/))
  end

  describe ".parse" do
    it "reads the file named by --config" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "custom.yml")
        File.write(path, "jobs: 7\n")
        expect(described_class.parse(["--config", path, "app"])).to(eq(jobs: 7))
      end
    end

    # Falling back to defaults would silently gate the wrong scope.
    it "fails loudly when the explicit --config path does not exist" do
      expect { described_class.parse(["--config", "nope.yml"]) }
        .to(raise_error(Kimera::UsageError, /no such config file: nope\.yml/))
    end

    it "falls back to .kimera.yml in the working directory" do
      Dir.mktmpdir do |dir|
        File.write(File.join(dir, ".kimera.yml"), "jobs: 3\n")
        Dir.chdir(dir) { expect(described_class.parse(["app"])).to(eq(jobs: 3)) }
      end
    end
  end

  describe ".prefer" do
    it "takes the command line over the config file, and the config over the default", :aggregate_failures do
      expect(described_class.prefer(["cli"], ["config"], ["default"])).to(eq(["cli"]))
      expect(described_class.prefer([], ["config"], ["default"])).to(eq(["config"]))
      expect(described_class.prefer([], [], ["default"])).to(eq(["default"]))
    end

    it "hands back a copy of the default, so a caller cannot mutate it" do
      default = ["app/**/*.rb"].freeze

      expect { described_class.prefer([], [], default) << "x" }.not_to(raise_error)
    end
  end
end
