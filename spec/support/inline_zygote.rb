# frozen_string_literal: true

require "kimera/execution/zygote"

# A zygote that runs its block in this process, through the same transport
# a forked child's reply takes, so a spec can inspect a fake adapter's runs.
class InlineZygote < Kimera::Execution::Zygote
  def call(&) = settle(JSON.generate(kept { outcome(&) }), nil)

  # A forked child's changes to the active mutant never reach its parent.
  def kept
    active = Kimera::RUNTIME.active
    yield
  ensure
    Kimera::RUNTIME.active = active
  end
end

# For a spec that drives the harness but is not about forking: a zygote
# mutant then fails the zygote's own specs instead of ending this process.
RSpec.shared_context("with an inline zygote") do
  # The harness of +options+, whose zygotes run their blocks in this process.
  def inline(**) = Kimera::Execution::Harness.build(zygote: InlineZygote.new, **)
end
