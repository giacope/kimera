# frozen_string_literal: true

class Kimera::CLI::TestShard
  OWN_DATABASE = <<~RUBY
    if defined?(ActiveRecord::Base) && defined?(ActiveSupport::Testing::Parallelization) &&
        ActiveSupport.respond_to?(:parallelize_test_databases) && ActiveSupport.parallelize_test_databases
      require "active_record/test_databases"
      ActiveSupport::Testing::Parallelization.before_fork_hooks.each(&:call)
      ActiveSupport::TestCase.parallel_worker_id = index if ActiveSupport::TestCase.respond_to?(:parallel_worker_id=)
      ActiveSupport::Testing::Parallelization.after_fork_hooks.each { |hook| hook.call(index) }
    end
  RUBY

  RSPEC = <<~RUBY.freeze
    require "rspec/core"
    count, index = %d, %d
    position = 0
    loaded = false
    RSpec.configure do |config|
      config.before(:suite) do
        loaded = true
        #{OWN_DATABASE}
      end
      config.define_derived_metadata { |meta| meta[:kimera_elsewhere] = !loaded && (position += 1) %% count != index }
      config.filter_run_excluding(kimera_elsewhere: true)
    end
    exit(RSpec::Core::Runner.run(ARGV))
  RUBY

  MINITEST = <<~RUBY.freeze
    require "minitest"
    require "zlib"
    count, index = %d, %d
    ENV["PARALLEL_WORKERS"] = "1"
    loaded = []
    Minitest::Test.singleton_class.prepend(
      Module.new do
        define_method(:runnable_methods) do
          tests = super()
          next tests unless loaded.include?(self)
          offset = Zlib.crc32(name.to_s)
          tests & tests.sort.select.with_index { |_test, position| (offset + position) %% count == index }
        end
      end
    )
    files = ARGV.dup
    ARGV.clear
    files.each { |file| require(File.expand_path(file)) }
    loaded.concat(Minitest::Runnable.runnables)
    #{OWN_DATABASE}
  RUBY

  ARGUMENTS = { "minitest" => ["-Itest", "-e", MINITEST] }.freeze

  def initialize(index, count)
    @index = index
    @count = count
  end

  def argv(framework)
    ARGUMENTS.fetch(framework.to_s, ["-e", RSPEC]).map { |argument| format(argument, @count, @index) }
  end
end
