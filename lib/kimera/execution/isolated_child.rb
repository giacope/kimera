# frozen_string_literal: true

require "rspec/core"
require "stringio"

begin
  RSpec::Core::ConfigurationOptions.new([]).configure(RSpec.configuration)
rescue StandardError, ScriptError
  nil
end
RSpec.configuration.output_stream = StringIO.new
RSpec.configuration.error_stream = StringIO.new
RSpec.configuration.deprecation_stream = StringIO.new

exit RSpec::Core::Runner.run(ARGV)
