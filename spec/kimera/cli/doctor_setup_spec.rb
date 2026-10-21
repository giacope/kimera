# frozen_string_literal: true

require "fileutils"
require "kimera/cli"
require "kimera/cli/doctor"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Doctor, :aggregate_failures) do
  def doctor(root = ".") = described_class.new(io: StringIO.new, errors: StringIO.new, root: root)

  # R3K1: an old prism crashed every command on Ruby 4.0 with a NameError.
  it "warns of a prism older than Ruby 4.0 needs" do
    expect(
      doctor.__send__(
        :prism, "1.6.0",
        "4.0.7"
      )
    ).to(
      eq(
        [
          "!", "Prism: 1.6.0 is older than Ruby 4.0.7 needs (1.9); " \
            "run `bundle update --conservative prism`"
        ]
      )
    )
    expect(doctor.__send__(:prism, "1.9.0", "4.0.7")).to(eq(["✓", "Prism: 1.9.0"]))
    expect(doctor.__send__(:prism, "1.6.0", "3.4.8")).to(eq(["✓", "Prism: 1.6.0"]))
  end

  # K3-1: on an engine doctor said no Rails-specific parallel setup was needed.
  it "treats an engine with a dummy app as Rails" do
    Dir.mktmpdir do |root|
      { "lib/blog/core.rb" => "class Blog::Core < Rails::Engine\nend\n", "spec/dummy/config/application.rb" => "" }
        .each do |path, body|
        FileUtils.mkdir_p(File.dirname(File.join(root, path)))
        File.write(File.join(root, path), body)
      end
      expect(doctor(root).__send__(:rails).first).to(eq("!"))
      FileUtils.rm(File.join(root, "lib/blog/core.rb"))
      expect(doctor(root).__send__(:rails).first).to(eq("✓"))
    end
  end
end
