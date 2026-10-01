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

  HARNESS = File.expand_path("..", __dir__)
  FRAMES = 5

  private

  def frames(backtrace)
    Array(backtrace).take_while { |frame| !frame.start_with?(HARNESS) }.first(FRAMES)
  end

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

require_relative "adapter_registry"
