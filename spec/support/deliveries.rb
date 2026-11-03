# frozen_string_literal: true

# The delivery Kimera::CLI::Run::Cycle hands its emission, with the plain
# defaults wherever a spec names no setting: no saved report, text, no
# metadata, coverage hinted at, no log, no scope notes and no summary.
module Deliveries
  PLAIN = { path: nil, format: "text", metadata: nil, coverage: :hint, log: nil, scope: [], summary: nil }.freeze

  def delivery(**settings)
    path, format, metadata, coverage, log, scope, summary = PLAIN.merge(settings).values_at(*PLAIN.keys)
    Kimera::CLI::Run::Emission::Delivery.new(
      Kimera::CLI::Run::Emission::Page.new(path, scope, coverage),
      Kimera::CLI::Run::Emission::Copies.new(path, log, summary), format, metadata
    )
  end
end

RSpec.configure { |config| config.include(Deliveries) }

# An emission that keeps what a delivery asked of it: the path it saved to
# (nil when it only rendered), the scope notes and coverage it rendered with,
# the format it presented in and the run metadata of the document.
class FakeEmission
  attr_reader :heard

  def initialize
    @heard = {}
  end

  def rendered(_report, _registry, scope:, coverage:) = record(path: nil, scope: scope, coverage: coverage)

  def saved(_report, _registry, path, scope:, coverage:) = record(path: path, scope: scope, coverage: coverage)

  def present(_text, format, document) = @heard.merge!(format: format, metadata: document["run"])

  private

  def record(**heard)
    @heard.merge!(heard)
    ""
  end
end
