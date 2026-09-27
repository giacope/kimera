# frozen_string_literal: true

module Kimera
  module Status
    KILLING = %i[killed timeout error].freeze

    UNJUDGED = %i[no_coverage ignored isolated_only unmutatable harness_error].freeze

    REPORTED =
      ([:survived] + (KILLING - [:killed]) + %i[no_coverage harness_error ignored isolated_only unmutatable]).freeze

    SELF_SUSPECT = ((KILLING - [:killed]) + [:survived]).freeze
  end

  MutantResult =
    Struct.new(
      :mutant_id, :status, :file, :duration, :failing_tests, :covering_tests,
      :detail, :verdict,
      keyword_init: true
    ) do
      def duration
        self[:duration] || 0.0
      end

      def killed?
        Status::KILLING.include?(status)
      end

      def lapsed?
        Status::KILLING.include?(verdict)
      end

      def isolated(detail)
        self.class.new(mutant_id: mutant_id, status: :isolated_only, file: file, duration: duration, detail: detail)
      end

      def waive
        self.class.new(**self.class.outcome(outcome), **waiver, mutant_id: mutant_id, file: file)
      end

      def waiver
        { status: :ignored, verdict: status, detail: ["ignored (#{status})", detail].compact.join(": ") }
      end

      def covered?
        !Status::UNJUDGED.include?(status)
      end

      def message
        { t: "result", id: mutant_id, status: status.to_s }
          .merge(ms: duration, fails: failing_tests, cover: covering_tests, detail: detail)
      end

      def to_h
        identity.merge(outcome)
      end

      def identity
        { "mutant_id" => mutant_id, "status" => status.to_s, "file" => file }.merge(judged)
      end

      def judged = verdict ? { "verdict" => verdict.to_s } : {}

      def outcome
        { "duration" => duration, "failing_tests" => failing_tests }
          .merge("covering_tests" => covering_tests, "detail" => detail)
      end
      class << self
        def waived(id, file)
          new(mutant_id: id, status: :ignored, file: file, detail: "marked equivalent (ignored)")
        end

        def from_h(hash)
          new(**identity(hash), **outcome(hash))
        end

        def identity(hash)
          { mutant_id: hash["mutant_id"], status: hash["status"].to_sym, file: hash["file"] }
            .merge(verdict: hash["verdict"]&.to_sym)
        end

        def outcome(hash)
          { duration: hash["duration"], failing_tests: hash["failing_tests"] }
            .merge(covering_tests: hash["covering_tests"], detail: hash["detail"])
        end
      end
    end
end
