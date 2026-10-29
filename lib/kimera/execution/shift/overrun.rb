# frozen_string_literal: true

require_relative "lapse"

class Kimera::Execution::Shift::Overrun
  include Kimera::Execution::Shift::Lapse

  def initialize(test, runs, control, explainer)
    @test = test
    @runs = runs
    @control = control
    @explainer = explainer
  end

  def detail = @explainer.explain(@test, @runs, @control)
end
