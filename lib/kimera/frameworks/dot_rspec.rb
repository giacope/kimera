# frozen_string_literal: true

require "rspec/core"

module Kimera
  module Frameworks
  end
end

class Kimera::Frameworks::DotRspec
  class Unparsed
    def configure(_config); end

    def options = {}
  end

  def configure(config)
    requires
    parsed.configure(config)
  # rubocop:disable-next Kata/FailFast -- options the project's .rspec cannot apply leave RSpec's defaults: the tests require their helpers themselves and raise there
  rescue StandardError, ScriptError
    nil
  end

  def preload(config)
    config.requires = requires
  # rubocop:disable-next Kata/FailFast -- preloading the .rspec requires is a head start: each test file requires its helpers again and raises there
  rescue StandardError, ScriptError
    nil
  end

  private

  def parsed
    @_parsed ||= RSpec::Core::ConfigurationOptions.new([])
  rescue StandardError, ScriptError
    Unparsed.new
  end

  def requires = @_requires ||= Array(parsed.options.delete(:requires))
end
