# frozen_string_literal: true

require_relative "../error"

class Kimera::Frameworks::SuiteRegistry
  BUILT_IN = { "rspec" => "rspec_suite", "minitest" => "minitest_suite" }.freeze

  def initialize(built_in = BUILT_IN)
    @built_in = built_in
    @suites = {}
  end

  def load(name)
    built_in(name.to_s)
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

  def built_in(name)
    return unless @built_in.key?(name)
    require_relative(@built_in.fetch(name))
  end

  def unloadable(name, error)
    "framework #{name} is configured but cannot be loaded (#{error.message}); " \
      "set framework: rspec or minitest in .kimera.yml, or add it to the Gemfile"
  end
end

Kimera::Frameworks::SUITES = Kimera::Frameworks::SuiteRegistry.new
