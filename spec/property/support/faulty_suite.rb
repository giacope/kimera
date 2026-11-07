# frozen_string_literal: true

require "json"
require "kimera/frameworks/suite"

class OfferTap
  def initialize(io, log)
    @io = io
    @log = log
    @served = 0
  end

  def recheck? = @offer.fetch("recheck", false)

  def id = @offer.fetch("id")

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

class FaultySuite
  FAILING = %i[killed requeue].freeze

  def initialize(script, offers)
    @script = script
    @offers = offers
    @behaviors = {}
    @runs = Hash.new(0)
  end

  def test_ids = ["t"]

  def run(ids)
    active = Kimera::RUNTIME.active
    failed = active ? on(active) : behavior(@offers.id) == :requeue
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
