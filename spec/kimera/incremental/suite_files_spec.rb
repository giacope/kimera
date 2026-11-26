# frozen_string_literal: true

require "fileutils"
require "kimera/incremental/suite_files"
require "tmpdir"

RSpec.describe(Kimera::Incremental::SuiteFiles) do
  def configuration = %w[.rspec .rspec-local Gemfile.lock config/**/* db/schema.rb db/structure.sql]

  it "reads each pattern and everything under its fixed top folder, once" do
    globs = described_class.new(["spec/**/*_spec.rb", "spec/unit/*_spec.rb", "test/a_test.rb"]).globs
    expect(globs).to(eq(%w[spec/**/*_spec.rb spec/unit/*_spec.rb test/a_test.rb spec/**/* test/**/*] + configuration))
  end

  it "reads no folder for a pattern that starts with a glob, names a top-level file or is absolute" do
    patterns = ["**/*_spec.rb", "a_spec.rb", "{x,y}/a.rb", "/spec/a_spec.rb"]
    expect(described_class.new(patterns).globs).to(eq(patterns + configuration))
  end

  it "lists the files under a root that its globs match" do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p([File.join(root, "spec/support"), File.join(root, "lib")])
      FileUtils.touch(%w[spec/a_spec.rb spec/support/helper.rb lib/a.rb].map { |path| File.join(root, path) })
      expect(described_class.new("spec/a_spec.rb").files(root))
        .to(contain_exactly("spec/a_spec.rb", "spec/a_spec.rb", "spec/support", "spec/support/helper.rb"))
    end
  end

  it "takes a single pattern" do
    expect(described_class.new("spec/a_spec.rb").globs).to(eq(%w[spec/a_spec.rb spec/**/*] + configuration))
  end
end
