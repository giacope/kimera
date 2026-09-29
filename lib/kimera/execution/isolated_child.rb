# frozen_string_literal: true

require "json"
require "rspec/core"
require "stringio"
require_relative "../support/test_exit"

begin
  RSpec::Core::ConfigurationOptions.new([]).configure(RSpec.configuration)
rescue StandardError, ScriptError
  nil
end
output = StringIO.new
RSpec.configuration.output_stream = output
RSpec.configuration.error_stream = StringIO.new
RSpec.configuration.deprecation_stream = StringIO.new

RSpec.configuration.before(:suite) do
  RSpec.world.all_examples.each { |example| example.extend(Kimera::TestExit::Example) }
end

ledger, request, pulse = ARGV
RSpec.configuration.prepend_before(:example) { File.write(pulse, ".", mode: "a") } if pulse
locations = JSON.parse(File.read(request, encoding: Encoding::UTF_8)).fetch("tests")
code = RSpec::Core::Runner.run(locations)

failed = RSpec.world.all_examples.select { |example| example.execution_result.status == :failed }
outside = RSpec.world.non_example_failure ? 1 : 0
report = { failures: failed.size + outside, failing: failed.map(&:id) }
report[:load_error] = output.string.strip[0, 4000] if outside.positive?
File.write(ledger, JSON.generate(report))

exit code
