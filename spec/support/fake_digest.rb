# frozen_string_literal: true

# What a run tells the person running it, as Kimera::CLI::Run::Digest says it:
# it writes down each thing it was asked to say, in order.
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

  # Each report it emitted, with the registry and what its delivery asked of the emission.
  def emitted = @said.filter_map { |kind, *heard| heard if kind == :emit }
end

# The warnings and the gate of a run, as Kimera::CLI::Run::Alerts gives them:
# its gate answers the status it was given and writes down each report it
# gated, with the settings it gated it by, and the ignore entries it was told
# are stale or moved.
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
