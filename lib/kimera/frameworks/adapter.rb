# frozen_string_literal: true

require_relative "../error"

module Kimera
  module Frameworks
    RunOutcome =
      Struct.new(:passed, :failed_ids, :failures, keyword_init: true) do
        def passed?
          passed
        end

        def failures
          self[:failures] || {}
        end

        def verdict
          passed? ? [:survived, []] : [:killed, failed_ids]
        end
      end
  end
end

class Kimera::Frameworks::Adapter
  def source(files)
    raise(NotImplementedError)
  end

  def test_ids
    raise(NotImplementedError)
  end

  def start; end

  def finish; end

  def run(ids)
    raise(NotImplementedError)
  end

  def describe(id)
    id
  end

  def reproduce(ids)
    "rspec #{(ids & test_ids).join(" ")} --order defined"
  end

  @registry ||= {}

  NO_LOADER = -> {}
  ADAPTER_LOADERS = {
    "rspec" => lambda do
      require_relative "rspec_adapter"
    end,
    "minitest" => lambda do
      require_relative "minitest_adapter"
    end
  }.freeze

  class << self
    attr_reader :registry

    def load(name)
      ADAPTER_LOADERS.fetch(name.to_s, NO_LOADER).call
      fetch(name).build
    rescue LoadError => error
      raise(Kimera::Error, unloadable(name, error))
    end

    def unloadable(name, error)
      "framework #{name} is configured but cannot be loaded (#{error.message}); " \
        "set framework: rspec or minitest in .kimera.yml, or add it to the Gemfile"
    end

    def register(name, klass)
      registry[name.to_s] = klass
    end

    def fetch(name)
      registry.fetch(name.to_s) do
        raise(Kimera::Error, "unknown test framework adapter: #{name}")
      end
    end
  end

  private

  def each_test_file(files, &)
    ARGV.clear
    Array(files).each { |file| load_test_file(file, &) }
  end

  def load_test_file(file)
    yield(File.expand_path(file))
  rescue StandardError, ScriptError => error
    raise(Kimera::Error, "cannot load test file #{file} (#{error.class}: #{error.message})")
  end
end
