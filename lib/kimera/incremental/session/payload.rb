# frozen_string_literal: true

class Kimera::Incremental::Session::Payload
  def initialize(data)
    @data = data
  end

  def session = Kimera::Incremental::Session.new(**attributes)

  private

  def attributes
    fields = { leaks: leaks, meta: @data["meta"] || {} }
    fields[:results] =
      keys(@data["results"]) do |hash|
        Kimera::MutantResult.from_h(hash).tap { |result| result.killing_tests = hash["killing_tests"] }
      end
    fields[:fingerprints] = keys(@data["fingerprints"]) { |fingerprint| fingerprint }
    fields
  end

  def leaks
    Array(@data["leaks"]).map { |hash| Kimera::LeakReport.new(mutant_id: hash["mutant_id"], detail: hash["detail"]) }
  end

  def keys(hash)
    Hash(hash).to_h { |id, value| [Integer(id, 10), yield(value)] }
  end
end
