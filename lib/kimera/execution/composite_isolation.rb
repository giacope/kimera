# frozen_string_literal: true

require_relative "isolation"

class Kimera::Execution::CompositeIsolation
  def initialize(strategies)
    @given = strategies
  end

  def around(&block)
    strategies.reverse.reduce(block) do |inner, strategy|
      -> { strategy.around(&inner) }
    end.call
  end

  def reset!
    strategies.each(&:reset!)
  end

  private

  def strategies = @_strategies ||= Array(@given)
end
