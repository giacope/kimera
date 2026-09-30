# frozen_string_literal: true

require "json"
require "kimera/frameworks/adapter"

# The request pipe as Shift reads it (Shift::Channel calls #gets). Logs each
# offer as the scripted children do, "id recheck first?", and remembers it,
# so the adapter knows whether the mutant it runs is a recheck.
class OfferTap
  def initialize(io, log)
    @io = io
    @log = log
    @served = 0
  end

  def recheck? = @offer.fetch("recheck", false)

  def gets
    @io.gets.tap { |line| note(JSON.parse(line)) if line }
  end

  private

  def note(offer)
    @offer = offer
    File.write(@log, "#{offer["id"]} #{recheck?} #{@served.zero?}\n", mode: "a")
    @served += 1
  end
end

# A framework adapter with one test that does to each mutant what the
# mutant's script says for the offer that brought it (warm or recheck), so
# that the real Shift, not a script, decides what goes down the pipe:
# - killed: fails with the mutant on, passes with it off;
# - survived: passes;
# - leak: killed, then passes when LeakGuard runs it again;
# - requeue: fails with the mutant off too (a Suspect: requeued warm, a
#   Doubt and so harness_error on a recheck);
# - tainted: outlasts the soft timeout (a timeout verdict ends the shift);
# - crash: the process exits;
# - hang: the process sleeps through the soft timeout, until the parent's
#   watchdog kills it.
# Kimera::Runtime.active names the mutant on each run a Trial makes, and is
# nil on its control run, which belongs to the mutant run before it.
class FaultyAdapter
  FAILING = %i[killed requeue].freeze

  def initialize(script, offers)
    @script = script
    @offers = offers
    @behaviors = {}
    @runs = Hash.new(0)
  end

  def test_ids = ["t"]

  def run(ids)
    active = Kimera::Runtime.active
    @current = active if active
    failed = active ? on(active) : behavior(@current) == :requeue
    Kimera::Frameworks::RunOutcome.new(passed: !failed, failed_ids: failed ? ids : [])
  end

  private

  def behavior(id) = @behaviors[id] ||= @script.fetch(id - 1)[@offers.recheck? ? 1 : 0]

  def on(id)
    @runs[id] += 1
    case behavior(id)
    when :crash then exit!(1)
    when :hang then Thread.handle_interrupt(Object => :never) { sleep(60) }
    when :tainted then sleep(5)
    when :leak then @runs[id] <= 2
    else FAILING.include?(behavior(id))
    end
  end
end
