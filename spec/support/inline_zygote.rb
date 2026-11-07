# frozen_string_literal: true

require "kimera/execution/zygote"

class InlineZygote < Kimera::Execution::Zygote
  def call(&) = settle(JSON.generate(kept { outcome(&) }), nil)

  def kept
    active = Kimera::RUNTIME.active
    yield
  ensure
    Kimera::RUNTIME.active = active
  end
end

RSpec.shared_context("with an inline zygote") do
  def inline(**) = Kimera::Execution::Harness.build(zygote: InlineZygote.new, **)
end
