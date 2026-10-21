# frozen_string_literal: true

require "kimera/incremental/suite_files"

RSpec.describe(Kimera::Incremental::SuiteFiles) do
  it "reads each pattern and everything under its fixed top folder, once" do
    globs = described_class.new(["spec/**/*_spec.rb", "spec/unit/*_spec.rb", "test/a_test.rb"]).globs
    expect(globs).to(eq(%w[spec/**/*_spec.rb spec/unit/*_spec.rb test/a_test.rb spec/**/* test/**/*]))
  end

  it "reads no folder for a pattern that starts with a glob, names a top-level file or is absolute" do
    expect(described_class.new(["**/*_spec.rb", "a_spec.rb", "{x,y}/a.rb", "/spec/a_spec.rb"]).globs.size).to(eq(4))
  end

  it "takes a single pattern" do
    expect(described_class.new("spec/a_spec.rb").globs).to(eq(%w[spec/a_spec.rb spec/**/*]))
  end
end
