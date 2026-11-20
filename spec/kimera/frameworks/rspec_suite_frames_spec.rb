# frozen_string_literal: true

require "fileutils"
require "kimera/frameworks/rspec_suite"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::Frameworks::RSpecSuite) do
  let(:dir) { Dir.mktmpdir }

  def isolated
    world = RSpec.world
    groups = world.example_groups.dup
    failed = world.non_example_failure
    streams = %i[output_stream error_stream deprecation_stream].map { |name| RSpec.configuration.public_send(name) }
    yield
  ensure
    world.non_example_failure = failed
    (world.example_groups - groups).each { |group| world.example_groups.delete(group) }
    restore(streams)
    FileUtils.remove_entry(dir)
  end

  def restore(streams)
    config = RSpec.configuration
    config.output_stream, config.error_stream, config.deprecation_stream = streams
  end

  def fixture
    File.join(dir, "frames_spec.rb").tap do |path|
      File.write(path, <<~RUBY)
        RSpec.describe "KimeraFrames" do
          def explode = raise("kaboom")

          it "raises" do
            explode
          end
        end
      RUBY
    end
  end

  def adapter
    original = $stderr
    $stderr = StringIO.new
    described_class.build.source([fixture])
  ensure
    $stderr = original
  end

  def failure
    loaded = adapter
    id = loaded.test_ids.find { |test| loaded[test].name == "KimeraFrames raises" }
    loaded.run([id]).to_h.fetch("failures")[id].lines(chomp: true)
  end

  it "follows the exception with the example's own frames" do
    isolated do
      expect(failure.first(3)).to(
        match(
          [
            eq("RuntimeError: kaboom"), match(/\A    \S*frames_spec\.rb:2:in '\S*explode'\z/),
            match(/\A    \S*frames_spec\.rb:5:in /)
          ]
        )
      )
    end
  end
end
