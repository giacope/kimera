# frozen_string_literal: true

require "kimera/scope/config"
require "tmpdir"

RSpec.describe(Kimera::Config) do
  def with_config(yaml)
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".kimera.yml"), yaml)
      yield(described_class.new(File.join(dir, ".kimera.yml")).options)
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
    Dir.mktmpdir { |dir| expect(described_class.new(File.join(dir, ".kimera.yml")).options).to(eq({})) }
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
      described_class.new(File.join(dir, ".kimera.yml")).options
    end
  end

  def accepted = { file: "app/models/old.rb", line: 4, label: "== => !=", reason: "pre-adoption debt" }

  it "keeps a reasoned baseline file's entries apart from the local ignore entries", :aggregate_failures do
    options = with_baseline
    expect(options.fetch(:ignore)).to(eq(normalized_ignore))
    expect(options.fetch(:baseline_ignore)).to(eq([accepted]))
  end

  def ignores(options) = described_class::Ignores.new(options).rules

  it "applies baseline entries after local ones unless --no-baseline cleared baseline", :aggregate_failures do
    options = with_baseline
    expect(ignores(options)).to(eq(normalized_ignore + [accepted]))
    expect(ignores(options.merge(baseline: false))).to(eq(normalized_ignore))
    expect(ignores({})).to(eq([]))
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
        expect(described_class.parse(["--config", path, "app"]).options).to(eq(jobs: 7))
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
        Dir.chdir(dir) { expect(described_class.parse(["app"]).options).to(eq(jobs: 3)) }
      end
    end
  end

  describe described_class::Precedence do
    def prefer(cli, configured, default) = described_class.new(cli, configured).chosen(default)

    it "takes the command line over the config file, and the config over the default", :aggregate_failures do
      expect(prefer(["cli"], ["config"], ["default"])).to(eq(["cli"]))
      expect(prefer([], ["config"], ["default"])).to(eq(["config"]))
      expect(prefer([], [], ["default"])).to(eq(["default"]))
    end

    it "hands back a copy of the default, so a caller cannot mutate it" do
      default = ["app/**/*.rb"].freeze

      expect { prefer([], [], default) << "x" }.not_to(raise_error)
    end
  end

  describe Kimera::Config::Attribution do
    def attribution(**options) = described_class.new(options)

    it "takes any or unit, defaulting to any" do
      modes = [nil, "unit", :any].map { |mode| attribution(attribution: mode).mode }
      expect(modes).to(eq(%w[any unit any]))
    end

    it "rejects any other mode, naming the choices" do
      expect { attribution(attribution: "strict").mode }
        .to(raise_error(Kimera::UsageError, 'unknown attribution "strict" (choose: any, unit)'))
    end

    it "reads a config mapping, wrapping a lone pattern in a list", :aggregate_failures do
      expect(attribution.rules).to(eq({}))
      expect(attribution(unit_tests: { "lib/**/*.rb" => "t/{name}.rb", a: %w[b c] }).rules)
        .to(eq("lib/**/*.rb" => ["t/{name}.rb"], "a" => %w[b c]))
    end

    it "reads --unit-tests GLOB=PATTERN pairs over the config's, splitting at the first =" do
      given = attribution(cli_unit_tests: ["lib/**/*.rb=t/{name}=x.rb"], unit_tests: { "a" => "b" })
      expect(given.rules).to(eq("lib/**/*.rb" => ["t/{name}=x.rb"]))
    end

    it "rejects a pair without both halves" do
      %w[lib/**/*.rb =t.rb lib=].each do |bad|
        expect { attribution(cli_unit_tests: [bad]).rules }
          .to(raise_error(Kimera::UsageError, "--unit-tests takes SOURCE_GLOB=TEST_PATTERN, got #{bad.inspect}"))
      end
    end
  end
end
