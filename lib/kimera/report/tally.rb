# frozen_string_literal: true

require_relative "../support/duration"

module Kimera
  module Report
  end
end

class Kimera::Report::Tally
  BAR_WIDTH = 24
  ALWAYS_SHOWN = %i[killed survived].freeze

  def initialize
    @total = 0
    @counts = {}
    @label = nil
    @started = 0.0
  end

  def begin!(total, label, now)
    @total = total
    @label = label
    @started = now
    @counts = {}
  end

  def count!(status)
    @counts[status] = @counts.fetch(status, 0) + 1
  end

  def done = @counts.values.sum

  def complete? = done >= @total

  def running? = @total.positive?

  def line(now)
    ["#{@label} #{bar}", "#{done}/#{@total}", "#{percent}%", *pace(now), elapsed(now)].join("  ")
  end

  private

  def statuses = @counts.keys.compact

  def pace(now)
    parts = statuses.empty? ? [] : [breakdown]
    parts << rate(now) if done.positive?
    parts << eta(now) unless complete? || done.zero?
    parts
  end

  def bar
    filled = (done * BAR_WIDTH) / @total
    head = filled.between?(1, BAR_WIDTH - 1) ? ">" : ""
    "[#{"=" * [filled - head.size, 0].max}#{head}#{" " * (BAR_WIDTH - filled)}]"
  end

  def percent = (done * 100) / @total

  def breakdown
    (ALWAYS_SHOWN + statuses).uniq.filter_map { |status| counted(status) }.join(" ")
  end

  def counted(status)
    "#{status}=#{@counts.fetch(status, 0)}"
  end

  def elapsed(now) = clock(Integer(now - @started))

  def rate(now)
    seconds = now - @started
    return "rate=—" if seconds <= 0
    format("%.1f/s", done / seconds)
  end

  def eta(now)
    seconds = now - @started
    return "ETA —" if seconds <= 0
    "ETA #{clock(Integer((@total - done) / (done / seconds)))}"
  end

  def clock(seconds) = Kimera::Duration.new(seconds).clock
end
