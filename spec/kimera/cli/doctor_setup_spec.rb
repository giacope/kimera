# frozen_string_literal: true

require "fileutils"
require "kimera/cli"
require "kimera/cli/doctor"
require "kimera/cli/prism_check"
require "stringio"
require "tmpdir"

RSpec.describe(Kimera::CLI::Doctor, :aggregate_failures) do
  def doctor(root = ".") = described_class.new(io: StringIO.new, errors: StringIO.new, root: root)

  # R3K1: an old prism crashed every command on Ruby 4.0 with a NameError.
  it "warns of a prism older than Ruby 4.0 needs" do
    old = "Prism: 1.6.0 is older than Ruby 4.0.7 needs (1.9); run `bundle update --conservative prism`"
    checks =
      [%w[1.6.0 4.0.7], %w[1.9.0 4.0.7], %w[1.6.0 3.4.8]]
        .map { |version, ruby| Kimera::CLI::PrismCheck.new(version: version, ruby: ruby).check }
    expect(checks).to(eq([["!", old], ["✓", "Prism: 1.9.0"], ["✓", "Prism: 1.6.0"]]))
  end

  it "reads a two-part Ruby version" do
    expect(Kimera::CLI::PrismCheck.new(version: "1.8.1", ruby: "4.0").check.first).to(eq("!"))
  end

  it "checks the prism in use by default" do
    expect(Kimera::CLI::PrismCheck.new.check).to(eq(["✓", "Prism: #{Prism::VERSION}"]))
  end

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
