# frozen_string_literal: true

# R6B2-M1: a suite may turn on Warning[:strict_unused_block] and raise every
# warning (dry-rb's spec_helper does), and kimera runs its scheduler and its
# verdicts in that suite's process. So kimera's own suite runs its lib the same
# way: a block passed to a method that ignores it, where either side is in lib,
# raises in the example that reaches it, and fails the suite should kimera
# rescue that error on the way.
Warning[:strict_unused_block] = true

module StrictBlocks
  LIB = "#{File.expand_path("../../lib", __dir__)}/".freeze
  IGNORED = Thread::Queue.new

  def warn(message, **)
    return super unless message.include?("may be ignored") && message.include?(LIB)
    IGNORED << message
    raise(message)
  end
end

Warning.singleton_class.prepend(StrictBlocks)

RSpec.configure do |config|
  config.after(:suite) do
    ignored = Array.new(StrictBlocks::IGNORED.size) { StrictBlocks::IGNORED.pop }.uniq
    raise(RuntimeError, "blocks ignored in lib:\n#{ignored.join}") if ignored.any?
  end
end
