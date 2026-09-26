# frozen_string_literal: true

require "json"
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

ledger, request = ARGV
locations = JSON.parse(File.read(request, encoding: Encoding::UTF_8)).fetch("tests")
code = RSpec::Core::Runner.run(locations)

failed = RSpec.world.all_examples.select { |example| example.execution_result.status == :failed }
outside = RSpec.world.non_example_failure ? 1 : 0
File.write(ledger, JSON.generate(failures: failed.size + outside, failing: failed.map(&:id)))

exit code
