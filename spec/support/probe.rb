# frozen_string_literal: true

# The channel a fixture suite loaded into this process reports through: its
# code pushes values, and the spec drains them once the fixture has run. A
# fixture whose verdict a spec steers reads KIMERA_PROBE instead.
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
