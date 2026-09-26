# frozen_string_literal: true

require "kimera/cli/run"
require "kimera/cli/synthesize"

RSpec.describe(Kimera::Flag) do
  describe "#define" do
    def parse(flag, argv)
      options = { value: nil, list: [] }
      OptionParser.new { |o| flag.define(o, options) }.parse(argv)
      options
    end

    it "assigns the parsed value to its key" do
      flag = described_class.build("--name NAME", :value, "help")

      expect(parse(flag, ["--name", "x"])[:value]).to(eq("x"))
    end

    it "appends every occurrence when it collects" do
      flag = described_class.build("--item X", :list, "help", collect: true)

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

  describe "FlagTable#parse" do
    it "turns a mistyped flag into a UsageError carrying the usage banner" do
      table = Kimera::FlagTable.new(banner: "Usage: kimera x", flags: [])

      expect { table.parse(["--nonsense"], {}) }
        .to(raise_error(Kimera::UsageError, /invalid option: --nonsense\nUsage: kimera x/))
    end
  end

  describe "the run table" do
    it "writes only keys the defaults declare" do
      declared = Dir.mktmpdir do |dir|
        Dir.chdir(dir) { Kimera::CLI::Run.new.__send__(:parse, []) }
      end.keys

      # resolve_globs consumes :cli_tests.
      expect(Kimera::CLI::Run::OPTIONS.keys - declared).to(eq([:cli_tests]))
    end

    it "defines each switch exactly once" do
      switches = Kimera::CLI::Run::OPTIONS.flags.map(&:switch)

      expect(switches.uniq).to(eq(switches))
    end
  end

  it "gives run and synthesize the same definition of the flags they share" do
    shared =
      lambda do |command|
        command::OPTIONS.flags.select { |flag| %i[registry operators].include?(flag.key) }
      end

    expect(shared.call(Kimera::CLI::Run)).to(eq(shared.call(Kimera::CLI::Synthesize)))
  end
end
