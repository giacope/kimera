# frozen_string_literal: true

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
