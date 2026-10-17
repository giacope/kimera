# frozen_string_literal: true

# Currency conversion through USD. Cross rates are memoised per thread (in
# Thread.current, i.e. fiber-local storage) and never expire on their own.
module Fx
  class UnknownCurrency < KeyError; end

  RATES = { "USD" => 1.0, "EUR" => 0.92, "GBP" => 0.79, "JPY" => 149.5, "CHF" => 0.88 }.freeze
  ZERO_DECIMAL = %w[JPY].freeze
  DEFAULT_SPREAD_BPS = 25

  module_function

  def cache
    Thread.current[:fx_cache] ||= {}
  end

  def rates
    Thread.current[:fx_rates] || RATES
  end

  def with_rates(overrides)
    saved = [Thread.current[:fx_rates], Thread.current[:fx_cache]]
    Thread.current[:fx_rates] = RATES.merge(overrides)
    Thread.current[:fx_cache] = {}
    yield
  ensure
    Thread.current[:fx_rates], Thread.current[:fx_cache] = saved
  end

  def rate(from, to)
    return 1.0 if from == to

    cache["#{from}/#{to}"] ||= begin
      per_usd_from = rates.fetch(from) { raise UnknownCurrency, "unknown currency #{from}" }
      per_usd_to = rates.fetch(to) { raise UnknownCurrency, "unknown currency #{to}" }
      (per_usd_to / per_usd_from).round(6)
    end
  end

  def convert(amount, from, to)
    raise ArgumentError, "negative amount" if amount.negative?

    round_for(to, amount * rate(from, to))
  end

  def quote(from, to, spread_bps: DEFAULT_SPREAD_BPS)
    mid = rate(from, to)
    half = mid * spread_bps / 20_000.0
    { bid: (mid - half).round(6), ask: (mid + half).round(6) }
  end

  def round_for(currency, value)
    ZERO_DECIMAL.include?(currency) ? value.round : value.round(2)
  end
end
