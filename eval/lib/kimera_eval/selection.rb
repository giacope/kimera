# frozen_string_literal: true

module KimeraEval
  class Selection
    include Enumerable

    def initialize(only, quick)
      @only = only
      @quick = quick
    end

    def each(&) = (@only ? CASES.select { |kind| @only.include?(kind::ID) } : CASES).each(&)

    def quick? = @quick
  end
end
