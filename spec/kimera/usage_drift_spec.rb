# frozen_string_literal: true

# `kimera skill` prints skills/kimera/SKILL.md for agents, and agents type
# what it says. When a command, flag, config key or operator is renamed or
# removed, these fail until the guide (and the README) say the new thing.
RSpec.describe(UsageDrift, :aggregate_failures) do
  def read(path) = File.read(File.expand_path("../../#{path}", __dir__), encoding: Encoding::UTF_8)

  let(:skill) { read("skills/kimera/SKILL.md") }

  it "tells agents only to type commands, flags, keys and operators the CLI accepts" do
    expect(described_class.new(skill).problems).to(eq([]))
  end

  it "shows the workflow commands an agent needs" do
    workflow = %w[init doctor run changed ci report mutant]
    expect(described_class.new(skill).commands).to(include(*workflow, "baseline create"))
  end

  it "tells people only to type what the CLI accepts in the README" do
    expect(described_class.new(read("README.md"), spans: false).problems).to(eq([]))
  end

  it "knows every command's options, so a new command is checked too" do
    expect(described_class::TABLES.keys).to(include(*Kimera::CLI::COMMAND_NAMES))
  end

  it "catches a stale command, flag, key and operator" do
    stale = <<~MARKDOWN
      ```sh
      kimera rnu
      kimera run --bogus --operators comparsion
      kimera baseline create --rerun
      ```
      Pass `--zzz`, or set `max_survivor: 0`.
      ```yaml
      paths: [app]
      max_survivor: 0
      ```
    MARKDOWN
    expect(described_class.new(stale).problems).to(
      contain_exactly(
        "unknown command: kimera rnu", "kimera run has no --bogus", "kimera baseline create has no --rerun",
        "no command has --bogus", "no command has --zzz", "no config key or ignore anchor: max_survivor:",
        "unknown operator: comparsion"
      )
    )
  end

  it "accepts negated switches, --help, and the operator groups" do
    fine = "```sh\nkimera run --no-progress --progress --help --operators all,rails\nkimera baseline --help\n```\n"
    expect(described_class.new(fine).problems).to(eq([]))
  end
end
