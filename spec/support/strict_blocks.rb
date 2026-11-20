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

class StrictGate
  def initialize(reporter)
    @reporter = reporter
  end

  def stop(_notification)
    ignored = Array.new(StrictBlocks::IGNORED.size) { StrictBlocks::IGNORED.pop }.uniq
    return if ignored.empty?
    @reporter.notify_non_example_exception(RuntimeError.new("blocks ignored in lib:\n#{ignored.join}"), "the suite")
  end
end

RSpec.configure { |config| config.reporter.register_listener(StrictGate.new(config.reporter), :stop) }
