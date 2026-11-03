# frozen_string_literal: true

require "kimera/cli/run"
require "kimera/cli/synthesize"

RSpec.describe(Kimera::Flag) do
  describe "#stored" do
    def parse(flag, argv)
      Kimera::FlagTable.new(banner: "Usage: kimera x", flags: [flag]).parse(argv, { value: nil, list: [] }).last
    end

    it "assigns the parsed value to its key" do
      flag = described_class.build("--name NAME", :value, "help")

      expect(parse(flag, ["--name", "x"])[:value]).to(eq("x"))
    end

    it "appends every occurrence when it collects" do
      flag = described_class.repeated("--item X", :list, "help")

      expect(parse(flag, ["--item", "a", "--item", "b"])[:list]).to(eq(%w[a b]))
    end

    it "coerces through the OptionParser type" do
      flag = described_class.build("--n N", :value, "help", type: Integer)

      expect(parse(flag, ["--n", "3"])[:value]).to(eq(3))
    end

    it "stores true for an argumentless switch and false for its negation" do
      flag = described_class.build("--[no-]on", :value, "help")

      expect([parse(flag, ["--on"])[:value], parse(flag, ["--no-on"])[:value]]).to(eq([true, false]))
    end
  end

  it "equals only another flag with the same signature, key and mode", :aggregate_failures do
    flag = described_class.build("--name NAME", :value, "help")
    expect(flag).to(eq(described_class.build("--name NAME", :value, "help")))
    expect(flag).not_to(eq(flag.to_h))
  end

  describe "FlagTable#parse" do
    it "turns a mistyped flag into a UsageError pointing at the command's help" do
      table = Kimera::FlagTable.new(banner: "Usage: kimera baseline create REPORT [options]", flags: [])

      expect { table.parse(["--nonsense"], {}) }
        .to(raise_error(Kimera::UsageError, "invalid option: --nonsense\nTry: kimera baseline create --help"))
    end

    it "folds OptionParser's suggestion into one line" do
      report = described_class.build("--report FILE", :report, "")
      table = Kimera::FlagTable.new(banner: "Usage: kimera x", flags: [report])

      expect { table.parse(["--reprot", "r.json"], {}) }
        .to(raise_error(Kimera::UsageError, "invalid option: --reprot; did you mean --report?\nTry: kimera x --help"))
    end
  end

  describe "the run table" do
    it "writes only keys the defaults declare" do
      declared = Dir.mktmpdir do |dir|
        Dir.chdir(dir) { Kimera::CLI::Run.new.__send__(:parse, []) }
      end.to_h.keys

      # resolve_globs consumes :cli_tests, and attribution :cli_unit_tests.
      keys = Kimera::CLI::RunOptions::OPTIONS.to_a.map { it.to_h[:key] }
      expect(keys - declared).to(eq(%i[cli_tests cli_unit_tests]))
    end

    it "defines each switch exactly once" do
      switches = Kimera::CLI::RunOptions::OPTIONS.to_a.map { it.to_h[:signature].grep(/\A-/) }

      expect(switches.uniq).to(eq(switches))
    end
  end

  def shared(command)
    keys = %i[registry operators]
    command::OPTIONS.to_a.select { |flag| keys.include?(flag.to_h[:key]) }
  end

  it "gives run and synthesize the same definition of the flags they share" do
    expect(shared(Kimera::CLI::RunOptions)).to(eq(shared(Kimera::CLI::Synthesize)))
  end
end
