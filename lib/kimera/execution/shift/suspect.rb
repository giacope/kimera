# frozen_string_literal: true

require_relative "../../results/result"

Kimera::Execution::Shift::Suspect =
  Data.define(:mutant_id, :test, :failure, :contradicted) do
    def final = Kimera::Execution::Shift::Doubt.new(**to_h)

    def evidence
      return "passed when rerun with the mutant still on" unless contradicted
      "also failed with the mutant switched off (#{reason})"
    end

    def reason
      failure.to_s.lines.first.to_s.strip.then { |line| line.empty? ? "no message" : line }
    end
  end

Kimera::Execution::Shift::Crawl =
  Class.new(Kimera::Execution::Shift::Suspect) do
    def final = Kimera::Execution::Shift::Lag.new(**to_h)
  end

Kimera::Execution::Shift::Doubt =
  Class.new(Kimera::Execution::Shift::Suspect) do
    def ruling(subject) = subject.verdict(:harness_error, detail: unjudged)

    def unjudged
      "#{test} #{evidence}, each run in a fresh process after the covering tests before it, and no other " \
        "covering test killed the mutant, so it can't be judged warm: fix the state that test depends on, " \
        "or judge the mutant with --isolated"
    end
  end

Kimera::Execution::Shift::Lag =
  Class.new(Kimera::Execution::Shift::Doubt) do
    def unjudged
      "#{test} #{failure}, so the timeout can't be laid on the mutant, and no other covering test killed it: " \
        "#{contradicted ? "fix the test, or raise" : "raise"} --soft-timeout well above the test's own time"
    end
  end
