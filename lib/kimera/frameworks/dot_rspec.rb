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
  rescue StandardError, ScriptError
    nil
  end

  def preload(config)
    config.requires = requires
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
