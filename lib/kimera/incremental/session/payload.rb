# frozen_string_literal: true

class Kimera::Incremental::Session::Payload
  def initialize(data)
    @data = data
  end

  def session(stamp) = Kimera::Incremental::Session.new(**attributes(stamp))

  private

  def attributes(stamp)
    meta = @data["meta"] || {}
    kept = meta["stamp"] == stamp
    { leaks: kept ? leaks : [], meta: stamp ? meta.merge("stamp" => stamp) : meta }
      .merge(results: kept ? results : {}, fingerprints: keys(@data["fingerprints"]) { |fingerprint| fingerprint })
  end

  def results
    keys(@data["results"]) { |hash| Kimera::MutantResult.from_h(hash) }
  end

  def leaks
    Array(@data["leaks"]).map { |hash| Kimera::LeakReport.new(mutant_id: hash["mutant_id"], detail: hash["detail"]) }
  end

  def keys(hash)
    Hash(hash).to_h { |id, value| [Integer(id, 10), yield(value)] }
  end
end
