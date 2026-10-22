# frozen_string_literal: true

require "fileutils"
require "kimera/cli"
require "kimera/cli/doctor"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Doctor, :aggregate_failures) do
  def doctor(root = ".") = described_class.new(io: StringIO.new, errors: StringIO.new, root: root)

  # K3-1: on an engine doctor said no Rails-specific parallel setup was needed.
  # The root, holding an engine and its dummy app.
  def engine(root)
    { "lib/blog/core.rb" => "class Blog::Core < Rails::Engine\nend\n", "spec/dummy/config/application.rb" => "" }
      .each do |path, body|
      FileUtils.mkdir_p(File.dirname(File.join(root, path)))
      File.write(File.join(root, path), body)
    end
    root
  end

  it "treats an engine with a dummy app as Rails" do
    Dir.mktmpdir { |root| expect(doctor(engine(root)).__send__(:rails).first).to(eq("!")) }
  end

  it "does not take a dummy app alone for Rails" do
    Dir.mktmpdir do |root|
      FileUtils.rm(File.join(engine(root), "lib/blog/core.rb"))
      expect(doctor(root).__send__(:rails).first).to(eq("✓"))
    end
  end
end
