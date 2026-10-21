# frozen_string_literal: true

require "rspec/core"

module Kimera
  module Frameworks
  end
end

# The project's .rspec, applied in two steps: its options when the adapter is
# built, its --require files with the test files, so kimera's load trace sees
# what spec_helper runs while the suite loads.
class Kimera::Frameworks::DotRspec
  def configure(config)
    requires
    parsed&.configure(config)
  rescue StandardError, ScriptError
    nil
  end

  def preload(config)
    config.requires = requires unless requires.empty?
  rescue StandardError, ScriptError
    nil
  end

  private

  def parsed
    @_parsed ||= RSpec::Core::ConfigurationOptions.new([])
  rescue StandardError, ScriptError
    nil
  end

  def requires = @_requires ||= Array(parsed&.options&.delete(:requires))
end
