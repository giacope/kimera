# frozen_string_literal: true

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
