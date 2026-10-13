# frozen_string_literal: true

require "kimera/execution/zygote"

# A zygote that runs its block in this process, through the same transport
# a forked child's reply takes, so a spec can inspect a fake adapter's runs.
class InlineZygote < Kimera::Execution::Zygote
  def call(&) = settle(JSON.generate(outcome(&)), nil)
end
