# frozen_string_literal: true

require_relative "../error"

class Kimera::Frameworks::SuiteRegistry
  def initialize(loaders = built_in)
    @loaders = loaders
  end

  def load(name)
    @loaders.fetch(name.to_s) { raise(Kimera::Error, "unknown test framework adapter: #{name}") }.call.build
  rescue LoadError => error
    raise(Kimera::Error, unloadable(name, error))
  end

  private

  def built_in
    {
      "rspec" => lambda do
        require_relative("rspec_suite")
        Kimera::Frameworks::RSpecSuite
      end,
      "minitest" => lambda do
        require_relative("minitest_suite")
        Kimera::Frameworks::MinitestSuite
      end
    }
  end

  def unloadable(name, error)
    "framework #{name} is configured but cannot be loaded (#{error.message}); " \
      "set framework: rspec or minitest in .kimera.yml, or add it to the Gemfile"
  end
end
