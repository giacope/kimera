# frozen_string_literal: true

Kimera::Execution::Shift::Suspect =
  Data.define(:mutant_id, :test, :failure, :control_failed) do
    def killed? = false

    def message
      { t: "requeue", id: mutant_id, detail: detail }
    end

    def detail
      "#{test} #{evidence}, so state left by earlier tests in its warm worker failed it, " \
        "not the mutant; the mutant was judged again on a fresh worker"
    end

    def ruling(_subject) = self

    def final = Kimera::Execution::Shift::Doubt.new(**to_h)

    def evidence
      return "passed when rerun with the mutant still on" unless control_failed
      "also failed with the mutant switched off (#{reason})"
    end

    def reason
      failure.to_s.lines.first.to_s.strip.then { |line| line.empty? ? "no message" : line }
    end
  end

Kimera::Execution::Shift::Doubt =
  Class.new(Kimera::Execution::Shift::Suspect) do
    def ruling(subject) = subject.verdict(:harness_error, detail: unjudged)

    def unjudged
      "#{test} #{evidence} even on a fresh worker, and no other covering test killed the mutant, " \
        "so it can't be judged warm: fix the state that test depends on, or judge the mutant with --isolated"
    end
  end
