# frozen_string_literal: true

require_relative "../error"
require_relative "seed"

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

        def expired? = false
      end
  end
end

# A test framework's suite as kimera drives it: it loads the test files, names
# each test by id, and runs the tests a mutant needs.
class Kimera::Frameworks::Suite
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

  def locate(_id) = {}

  def test_file(_id) = ""

  def catalog(ids) = (ids & test_ids).to_h { |id| [id, { "name" => describe(id) }.merge(locate(id))] }

  def reproduce(ids)
    "rspec #{(ids & test_ids).join(" ")} --order defined"
  end

  def plain(_ids, _out) = []

  def failed_plainly(_output, _out) = []

  HARNESS = File.expand_path("..", __dir__)
  FRAMES = 5
  DEPENDENCIES = %w[ast parser prism racc].freeze
  KIND_CLASH = /\A(\w+) is not a (?:class|module)\b/

  private

  def reseed(test)
    seed = Kimera::Seed.new
    Kernel.srand(seed.for(test)) if seed.value
  end

  def outcome(failed)
    Kimera::Frameworks::RunOutcome.new(passed: failed.empty?, failed_ids: failed.map(&:first), failures: failed.to_h)
  end

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
    raise(Kimera::Error, "cannot load test file #{file} (#{error.class}: #{error.message})#{clash(error)}")
  end

  def clash(error)
    name = error.message[KIND_CLASH, 1] if error.is_a?(TypeError)
    gem = name && owner(name)
    return "" unless gem
    "\n  #{name} is a top-level constant that #{gem}, a gem kimera runs on, defines in the process that loads " \
      "your suite, so the project's own #{name} cannot load beside it: put the project's #{name} in a namespace"
  end

  def owner(name)
    path = Object.const_source_location(name)&.first.to_s
    DEPENDENCIES.find { |gem| Gem.loaded_specs[gem]&.full_gem_path&.then { |root| path.start_with?("#{root}/") } }
  end
end

require_relative "suite_registry"
