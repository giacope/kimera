# frozen_string_literal: true

require "kimera/cli"
require "kimera/cli/rspec_options"
require "tmpdir"

# What a project's .rspec tells rspec to load and leave out (R6B4-M9), as
# globs from the project's root: rspec joins a pattern that does not start
# with its default path (spec, or --default-path) to it, and reads a comma as
# "or".
RSpec.describe(Kimera::CLI::RspecOptions, :aggregate_failures) do
  def options(text)
    Dir.mktmpdir do |root|
      File.write(File.join(root, ".rspec"), text) if text
      yield(described_class.new(root), root)
    end
  end

  it "reads --pattern and --exclude-pattern, spaced or with =" do
    options("--pattern spec/unit/**/*_spec.rb\n--exclude-pattern='spec/integration/**/*_spec.rb'") do |found|
      expect([found.tests, found.excluded]).to(eq([["spec/unit/**/*_spec.rb"], ["spec/integration/**/*_spec.rb"]]))
    end
  end

  it "joins a pattern to the default path, as rspec does, and splits a list" do
    options("-P **/*_test.rb --exclude-pattern \"./spec/a/*_spec.rb, slow/**\" --default-path checks") do |found|
      expect([found.tests, found.excluded])
        .to(eq([%w[checks/**/*_test.rb], %w[checks/spec/a/*_spec.rb checks/slow/**]]))
    end
    options("--exclude-pattern ./spec/a/*_spec.rb") { |found| expect(found.excluded).to(eq(["spec/a/*_spec.rb"])) }
  end

  it "reads nothing from no .rspec, or one it cannot split" do
    options(nil) { |found| expect([found.tests(["x"]), found.excluded]).to(eq([["x"], []])) }
    options("--exclude-pattern 'open") { |found| expect(found.excluded).to(eq([])) }
  end

  def left(root)
    File.join(root, "spec", "integration", "rails_spec.rb").tap do |file|
      FileUtils.mkdir_p(File.dirname(file))
      File.write(file, "")
    end
  end

  it "notes the test files kimera loads that .rspec leaves out" do
    options("--exclude-pattern spec/integration/*_spec.rb") do |found, root|
      note = [["!", format(described_class::LOADED, 1, "spec/integration/*_spec.rb")]]
      kept = "#{root}/spec/a_spec.rb"
      expect([found.loaded([left(root), kept]), found.loaded([kept])]).to(eq([note, []]))
    end
  end
end
