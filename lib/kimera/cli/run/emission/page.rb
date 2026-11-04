# frozen_string_literal: true

class Kimera::CLI::Run::Emission; end

class Kimera::CLI::Run::Emission::Page
  def initialize(path, scope, coverage)
    @path = path
    @scope = scope
    @coverage = coverage
  end

  def text(report, registry, emission)
    return emission.rendered(report, registry, scope: @scope, coverage: @coverage) unless @path
    emission.saved(report, registry, @path, scope: @scope, coverage: @coverage)
  end
end
