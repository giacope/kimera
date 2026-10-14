require_relative "tax"

module Quote
  CACHE = {}

  def self.rate(region)
    CACHE[region] ||= Tax.rate(region)
  end

  def self.exempt?(region)
    CACHE.fetch([:exempt, region]) { CACHE[[:exempt, region]] = Tax.exempt?(region) }
  end
end
