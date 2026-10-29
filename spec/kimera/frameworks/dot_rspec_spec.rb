# frozen_string_literal: true

require "kimera/frameworks/dot_rspec"
require "tmpdir"

RSpec.describe(Kimera::Frameworks::DotRspec) do
  # The part of RSpec's configuration DotRspec writes.
  let(:config) { Struct.new(:requires).new(:unset) }

  it "preloads no file when the project's .rspec does not parse" do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, ".rspec"), "--require \"unterminated\n")
      Dir.chdir(dir) { described_class.new.preload(config) }
    end
    expect(config.requires).to(eq([]))
  end
end
