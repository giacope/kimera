# frozen_string_literal: true

module Kimera
  class Status
    KILLING = %i[killed timeout error].freeze

    UNJUDGED = %i[no_coverage ignored isolated_only unmutatable harness_error].freeze

    def initialize(name)
      @name = name
    end

    def killing? = KILLING.include?(@name)

    def judged? = !UNJUDGED.include?(@name)
  end

  MutantResult =
    Data.define(
      :mutant_id, :status, :file, :duration, :failing_tests, :covering_tests,
      :detail, :verdict, :note, :killing_tests
    ) do
      def initialize(**fields) = super(**UNSET, **fields)

      def killed?
        Status.new(status).killing?
      end

      def lapsed?
        Status.new(verdict).killing?
      end

      def covered?
        Status.new(status).judged?
      end

      def status?(*statuses) = statuses.include?(status)

      def <=>(other) = mutant_id <=> other.mutant_id

      def entry = [mutant_id, self]

      def from(table) = table.fetch(mutant_id)

      def tick(progress) = progress.call(status)

      def covering = yield(covering_tests)

      def isolated(detail)
        self.class.new(mutant_id: mutant_id, status: :isolated_only, file: file, duration: took, detail: detail)
      end

      def unjudged(detail)
        self.class.new(mutant_id: mutant_id, status: :harness_error, file: file, detail: detail)
      end

      def unstaged(reason) = unjudged("#{reason}#{detail}")

      def suspected(statuses)
        reason = status?(*statuses) && yield(status, file)
        reason ? isolated(reason) : self
      end

      def credit = with(killing_tests: yield(mutant_id, Array(failing_tests)))

      def merged(fresh)
        kept = fresh.killed? || status?(:survived) ? fresh : self
        kept.with(covering_tests: [*covering_tests, *fresh.failing_tests].uniq)
      end

      def noting(judged, reason) = judged.with(note: "#{reason}#{detail}")

      def unreached = with(detail: unreached_detail)

      def narrowed(note) = detail.nil? || detail == unreached_detail ? with(detail: note) : self

      def waive
        self.class.new(
          mutant_id: mutant_id, file: file, duration: took, failing_tests: failing_tests,
          covering_tests: covering_tests, note: note, killing_tests: killing_tests,
          status: :ignored, verdict: status, detail: ["ignored (#{status})", detail].compact.join(": ")
        )
      end

      def message
        { t: "result", id: mutant_id, status: status.to_s }
          .merge(ms: took, fails: failing_tests, cover: covering_tests, detail: detail)
          .merge(killing_tests ? { kills: killing_tests } : {})
      end

      def to_h
        identity.merge(outcome)
      end
      protected(*members)
      private
      def took = duration || 0.0

      def unreached_detail
        "no test reached the code it mutates (other code on its line may have run); its file was loaded at boot"
      end

      def identity
        { "mutant_id" => mutant_id, "status" => status.to_s, "file" => file }.merge(judged)
      end

      def judged = verdict ? { "verdict" => verdict.to_s } : {}

      def outcome
        { "duration" => took, "failing_tests" => failing_tests }
          .merge("covering_tests" => covering_tests, "detail" => detail).merge(noted)
      end

      def noted = { "note" => note, "killing_tests" => killing_tests }.compact
      class << self
        def from_waiver(id, file)
          new(mutant_id: id, status: :ignored, file: file, detail: "marked equivalent (ignored)")
        end

        def from_h(hash)
          new(
            mutant_id: hash["mutant_id"], status: hash["status"].to_sym, file: hash["file"],
            verdict: hash["verdict"]&.to_sym, duration: hash["duration"], failing_tests: hash["failing_tests"],
            covering_tests: hash["covering_tests"], detail: hash["detail"], note: hash["note"],
            killing_tests: hash["killing_tests"]
          )
        end
      end
    end

  UNSET = MutantResult.members.to_h { |field| [field, nil] }.freeze
  private_constant(:UNSET)
end
