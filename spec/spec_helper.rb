# frozen_string_literal: true

if ENV["COVERAGE"] && RSpec.configuration.files_to_run.size == Dir.glob(File.join(__dir__, "**/*_spec.rb")).size
  require "simplecov"
  SimpleCov.start do
    enable_coverage :branch
    enable_coverage :method
    skip %r{/spec/}
    skip %r{/examples/}
    cover "lib/**/*.rb"
  end
end

require "kimera"

Dir[File.join(__dir__, "support", "**", "*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :expect }
  config.disable_monkey_patching!
  config.order = :defined
end
