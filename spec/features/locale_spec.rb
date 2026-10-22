# frozen_string_literal: true

require "English"
require "json"
require "shellwords"

# Under LANG=C, Ruby reads files and pipes as US-ASCII; kimera's own reads
# and the pipes between its processes must still carry UTF-8 test names and
# source.
RSpec.describe("kimera under the C locale (end-to-end)", :aggregate_failures) do
  def menu
    <<~RUBY
      # Prix en euros
      module Cafe
        def self.libellé(prix) = prix > 10 ? "cher — \#{prix} €" : "abordable ✓"
      end
    RUBY
  end

  def menu_spec
    <<~RUBY
      require_relative "../app/cafe"

      RSpec.describe Cafe do
        it("trouve 12 € « cher »") { expect(Cafe.libellé(12)).to eq("cher — 12 €") }
        it("trouve 10 € abordable ✓") { expect(Cafe.libellé(10)).to eq("abordable ✓") }
      end
    RUBY
  end

  def cli(root, *arguments)
    command = ["bundle", "exec", "ruby", File.join(test_repository_root, "exe", "kimera"), *arguments].shelljoin
    gemfile = File.join(test_repository_root, "Gemfile").shellescape
    `cd #{root.shellescape} && env LANG=C LC_ALL=C BUNDLE_GEMFILE=#{gemfile} #{command} 2>&1`
      .force_encoding(Encoding::UTF_8).then { |text| [text, $CHILD_STATUS.exitstatus] }
  end

  # The run's exit, each mutant's status and every test name, read as UTF-8.
  def run_facts(root)
    output, status = cli(root, "run", "app", "--tests", "spec/**/*_spec.rb", "--jobs", "2", "--no-progress")
    expect(status).to(eq(0), output)
    report = JSON.parse(File.read(File.join(root, "tmp", "kimera", "report.json"), encoding: Encoding::UTF_8))
    {
      statuses: report["results"].map { |row| row["status"] }.uniq,
      names: report["tests"].values.map { |test| test["name"] }
    }
  end

  it "runs, reports and shows a mutant with UTF-8 names and source, at --jobs 2" do
    test_tree({ "app/cafe.rb" => menu, "spec/cafe_spec.rb" => menu_spec }, "kimera-locale") do |root|
      expect(run_facts(root)).to(match(statuses: ["killed"], names: include("Cafe trouve 12 € « cher »")))
      expect(cli(root, "mutant", "1").first).to(include("in libellé"))
    end
  end
end
