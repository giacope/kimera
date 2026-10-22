# frozen_string_literal: true

require_relative "../error"

class Kimera::Frameworks::SuiteRegistry
  NO_LOADER = -> {}
  LOADERS = {
    "rspec" => lambda do
      require_relative "rspec_suite"
    end,
    "minitest" => lambda do
      require_relative "minitest_suite"
    end
  }.freeze

  def initialize
    @suites = {}
  end

  def load(name)
    LOADERS.fetch(name.to_s, NO_LOADER).call
    fetch(name).build
  rescue LoadError => error
    raise(Kimera::Error, unloadable(name, error))
  end

  def register(name, klass)
    @suites[name.to_s] ||= klass
  end

  def fetch(name)
    @suites.fetch(name.to_s) do
      raise(Kimera::Error, "unknown test framework adapter: #{name}")
    end
  end

  private

  def unloadable(name, error)
    "framework #{name} is configured but cannot be loaded (#{error.message}); " \
      "set framework: rspec or minitest in .kimera.yml, or add it to the Gemfile"
  end
end

Kimera::Frameworks::SUITES = Kimera::Frameworks::SuiteRegistry.new
