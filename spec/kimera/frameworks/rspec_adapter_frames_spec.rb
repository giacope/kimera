# frozen_string_literal: true

require "fileutils"
require "kimera/frameworks/rspec_adapter"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::Frameworks::RSpecAdapter) do
  let(:dir) { Dir.mktmpdir }

  # Loading a spec file registers groups in the global RSpec.world, so snapshot and restore it.
  around do |example|
    groups = RSpec.world.example_groups.dup
    streams = %i[output_stream error_stream deprecation_stream].map { |name| RSpec.configuration.public_send(name) }
    example.run
  ensure
    (RSpec.world.example_groups - groups).each { |group| RSpec.world.example_groups.delete(group) }
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

  # Hides RSpec's warning about re-pointing already-initialized streams.
  def adapter
    original = $stderr
    $stderr = StringIO.new
    described_class.build.source([fixture])
  ensure
    $stderr = original
  end

  it "follows the exception with the example's own frames", :aggregate_failures do
    loaded = adapter
    id = loaded.test_ids.find { |test| loaded.describe(test) == "KimeraFrames raises" }
    lines = loaded.run([id]).failures[id].lines(chomp: true)

    expect(lines.first).to(eq("RuntimeError: kaboom"))
    expect(lines[1]).to(match(/\A    \S*frames_spec\.rb:2:in '\S*explode'\z/))
    expect(lines[2]).to(match(/\A    \S*frames_spec\.rb:5:in /))
  end
end
