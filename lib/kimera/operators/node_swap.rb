# frozen_string_literal: true

require_relative "base"

class Kimera::Operators::NodeSwap < Kimera::Operators::Base
  class << self
    def define(key, mutations)
      Class.new(self) do
        const_set(:MUTATIONS, mutations.freeze)
        define_singleton_method(:key) { key }
      end
    end
  end

  def variants(node, **)
    swap = self.class::MUTATIONS[node.class]
    return unless swap
    solo(swap[:label], key, to: swap[:to])
  end
end
