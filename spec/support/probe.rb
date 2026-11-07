# frozen_string_literal: true

PROBE = Thread::Queue.new

module Probing
  def probed = Array.new(PROBE.size) { PROBE.pop }

  def steer(on)
    on ? ENV.store("KIMERA_PROBE", "on") : ENV.delete("KIMERA_PROBE")
    yield
  ensure
    ENV.delete("KIMERA_PROBE")
  end
end

RSpec.configure { |config| config.include(Probing) }
