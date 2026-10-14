limit = 20
settings = File.join(__dir__, "..", "config", "second.txt")
require_relative "../config/defaults"
SECOND_OVER = ->(value) { value > limit }
SECOND_NAME = -> { File.read(settings).strip if File.exist?(settings) && DEFAULTS[:named] }

module Second
  def self.over?(value) = SECOND_OVER.call(value)

  def self.name = SECOND_NAME.call
end
