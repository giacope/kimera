# frozen_string_literal: true

require_relative "../scope/config"
require_relative "../frameworks/load_path"
require_relative "checklist"
require_relative "doctor/examination"
require_relative "flag"
require_relative "instruments"
require_relative "verdict"

class Kimera::CLI::Doctor
  OPTIONS = Kimera::FlagTable.new(
    banner: "Usage: kimera doctor [--check-baseline [--jobs N]]",
    flags: [
      Kimera::Flag.build("--check-baseline", :check_baseline, "Run the configured test suite and verify it is green"),
      Kimera::Flag.build("--jobs N", :jobs, "Also run it split across N processes (default: jobs:)", type: Integer)
    ]
  )

  def initialize(io: $stdout, root: ".", instruments: Kimera::CLI::Instruments.new, **)
    @io = io
    @root = root
    @instruments = instruments
  end

  def run(argv)
    _, options = OPTIONS.parse(argv, { check_baseline: false })
    config = Kimera::Config.of(@root).options.merge(options.slice(:jobs))
    expose(config)
    examination = Kimera::CLI::Doctor::Examination.new(config, @root, @instruments, list)
    Kimera::CLI::Verdict.new(examination.checks(options)).outcome
  end

  private

  def expose(config, env = ENV)
    Kimera::Frameworks::LoadPath.new([], env: env).share(config[:load_path])
  end

  def list = Kimera::CLI::Checklist.new(@io)
end
