# frozen_string_literal: true

module Kimera
  module Execution
  end
end

class Kimera::Execution::Callback
  def initialize(filter)
    @filter = filter
  end

  def duplicate?(existing)
    case @filter
    when Proc then sourced?(existing)
    when Symbol, String then existing == @filter
    else alike?(existing)
    end
  end

  private

  def sourced?(existing)
    existing.is_a?(Proc) && existing.source_location&.first == @filter.source_location&.first
  end

  def alike?(existing)
    kind = @filter.class
    return false unless existing.instance_of?(kind)
    return true unless kind.method_defined?(:attributes)
    existing.attributes == @filter.attributes
  end
end
