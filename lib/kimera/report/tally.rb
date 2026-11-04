# frozen_string_literal: true

require_relative "../support/duration"

module Kimera
  module Report
  end
end

class Kimera::Report::Tally
  BAR_WIDTH = 24
  ALWAYS_SHOWN = %i[killed survived].freeze

  def initialize(total, label, started, counts = {}.freeze)
    @total = total
    @label = label
    @started = started
    @counts = counts
  end

  def counted(status) = self.class.new(@total, @label, @started, @counts.merge(status => count(status) + 1).freeze)

  def complete? = done >= @total

  def line(now)
    ["#{@label} #{bar}", "#{done}/#{@total}", "#{percent}%", *pace(now), elapsed(now)].join("  ")
  end

  def plain(now)
    ["kimera: #{@label} #{done}/#{@total} #{percent}%", *pace(now), "#{elapsed(now)} elapsed"].join("  ")
  end

  private

  def done = @counts.values.sum

  def count(status) = @counts.fetch(status, 0)

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
    (ALWAYS_SHOWN + statuses).uniq.map { |status| "#{status}=#{count(status)}" }.join(" ")
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
