# frozen_string_literal: true

require "json"
require "rspec/core"
require "stringio"
require "zlib"
require_relative "../exits/test_exit"
require_relative "../support/warnings"
require_relative "mirror_database"

output = StringIO.new
streams = { output_stream: output, error_stream: StringIO.new, deprecation_stream: StringIO.new }
redirect =
  lambda do
    streams.each do |name, stream|
      RSpec.configuration.public_send(:"#{name}=", stream) unless RSpec.configuration.public_send(name).equal?(stream)
    end
  end
redirect.call
begin
  RSpec::Core::ConfigurationOptions.new([]).configure(RSpec.configuration)
rescue StandardError, ScriptError
  nil
end
aborted = RSpec.world.wants_to_quit || RSpec.world.rspec_is_quitting
Kimera::Warnings::SILENCED.during(&redirect)

RSpec.configuration.before(:suite) do
  RSpec.world.all_examples.each { |example| example.extend(Kimera::TestExit::Example) }
end

ledger, request, pulse = ARGV
RSpec.configuration.prepend_before(:example) { File.write(pulse, ".", mode: "a") } if pulse
request = JSON.parse(File.read(request, encoding: Encoding::UTF_8))
RSpec.configuration.prepend_before(:suite) { Kimera::Execution::MirrorDatabase.new(request["slot"]).adopt }
if (seed = request["seed"])
  RSpec.configuration.prepend_before(:example) { |example| Kernel.srand((seed ^ Zlib.crc32(example.id)) % (2**31)) }
end
if request["first_failure"]
  RSpec.configuration.before(:suite) do
    requested = RSpec.world.all_examples
    stop = Object.new
    stop.define_singleton_method(:example_failed) do |notification|
      RSpec.world.wants_to_quit = true if requested.include?(notification.example)
    end
    RSpec.configuration.reporter.register_listener(stop, :example_failed)
  end
end
code = RSpec::Core::Runner.run(request.fetch("tests"))

failed = RSpec.world.all_examples.select { |example| example.execution_result.status == :failed }
outside = RSpec.world.non_example_failure || aborted ? 1 : 0
report = { failures: failed.size + outside, failing: failed.map(&:id) }
first = failed.first&.execution_result&.exception
report[:message] = "#{first.class}: #{first.message}"[0, 2000] if first
report[:load_error] = output.string.strip[0, 4000] if outside.positive?
File.write(ledger, JSON.generate(report))

exit code
