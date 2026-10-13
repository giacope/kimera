limit = 20
settings = File.join(__dir__, "..", "config", "second.txt")
require_relative "../config/defaults"

module Second
  OVER = ->(value) { value > limit }
  NAME = -> { File.read(settings).strip if File.exist?(settings) && DEFAULTS[:named] }

  def self.over?(value) = OVER.call(value)

  def self.name = NAME.call
end
