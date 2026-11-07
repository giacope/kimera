# frozen_string_literal: true

class FakeDigest
  attr_reader :said

  def initialize
    @said = []
  end

  def verbose(options) = @said.push([:verbose, options])

  def announce(_change, selected, ignored, files:) = @said.push([:announce, selected, ignored, files])

  def evaluating(ignored) = @said.push([:evaluating, ignored])

  def emit(report, registry, delivery)
    heard = FakeEmission.new.tap { |emission| delivery.deliver(report, registry, emission) }.heard
    @said.push([:emit, report, registry, heard])
  end

  def emitted = @said.filter_map { |kind, *heard| heard if kind == :emit }
end

class FakeAlerts
  attr_reader :gated, :warned

  def initialize(status = 0)
    @status = status
    @gated = []
    @warned = []
  end

  def gate(report, options)
    @gated.push([report, options])
    @status
  end

  def anchors(resolution) = resolution.alert(self)

  def stale(rule) = @warned.push([:stale, rule])

  def moved(shift) = @warned.push([:moved, shift])
end
