# frozen_string_literal: true

module KimeraEval
  class Context
    def initialize(checkout, sandbox, selection)
      @checkout = checkout
      @sandbox = sandbox
      @selection = selection
    end

    def judged(kind) = kind.new(@checkout, @sandbox, @selection).call
  end
end
