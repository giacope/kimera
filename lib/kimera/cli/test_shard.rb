# frozen_string_literal: true

module Kimera::CLI::TestShard
  RSPEC = <<~RUBY
    require "rspec/core"
    position = 0
    loaded = false
    RSpec.configure do |config|
      config.before(:suite) { loaded = true }
      config.define_derived_metadata { |meta| meta[:kimera_elsewhere] = !loaded && (position += 1) %% %d != %d }
      config.filter_run_excluding(kimera_elsewhere: true)
    end
    exit(RSpec::Core::Runner.run(ARGV))
  RUBY

  MINITEST = <<~RUBY
    require "minitest"
    require "zlib"
    loaded = []
    Minitest::Test.singleton_class.prepend(
      Module.new do
        define_method(:runnable_methods) do
          tests = super()
          next tests unless loaded.include?(self)
          offset = Zlib.crc32(name.to_s)
          tests & tests.sort.select.with_index { |_test, position| (offset + position) %% %d == %d }
        end
      end
    )
    files = ARGV.dup
    ARGV.clear
    files.each { |file| require(File.expand_path(file)) }
    loaded.concat(Minitest::Runnable.runnables)
  RUBY

  ARGUMENTS = { "minitest" => ["-Itest", "-e", MINITEST] }.freeze

  module_function

  def argv(framework, index, count)
    ARGUMENTS.fetch(framework.to_s, ["-e", RSPEC]).map { |argument| format(argument, count, index) }
  end
end
