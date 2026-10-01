# frozen_string_literal: true

class Kimera::Incremental::Session::Payload
  def initialize(data)
    @data = data
  end

  def session = Kimera::Incremental::Session.new(**attributes)

  private

  def attributes
    attrs = { leaks: leaks, meta: @data["meta"] || {} }
    attrs[:results] = keys(@data["results"]) { |hash| Kimera::MutantResult.from_h(hash) }
    attrs[:fingerprints] = keys(@data["fingerprints"]) { |fingerprint| fingerprint }
    attrs
  end

  def leaks
    Array(@data["leaks"]).map { |hash| Kimera::LeakReport.new(mutant_id: hash["mutant_id"], detail: hash["detail"]) }
  end

  def keys(hash)
    Hash(hash).to_h { |id, value| [Integer(id, 10), yield(value)] }
  end
end
