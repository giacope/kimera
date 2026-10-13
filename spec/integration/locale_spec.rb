# frozen_string_literal: true

require "English"
require "fileutils"
require "json"
require "shellwords"
require "tmpdir"

# Under LANG=C, Ruby reads files and pipes as US-ASCII; kimera's own reads
# and the pipes between its processes must still carry UTF-8 test names and
# source.
RSpec.describe("kimera under the C locale (end-to-end)", :aggregate_failures) do
  def project(root)
    FileUtils.mkdir_p([File.join(root, "app"), File.join(root, "spec")])
    File.write(File.join(root, "app", "cafe.rb"), <<~RUBY)
      # Prix en euros
      module Cafe
        def self.libellé(prix) = prix > 10 ? "cher — \#{prix} €" : "abordable ✓"
      end
    RUBY
    File.write(File.join(root, "spec", "cafe_spec.rb"), <<~RUBY)
      require_relative "../app/cafe"

      RSpec.describe Cafe do
        it("trouve 12 € « cher »") { expect(Cafe.libellé(12)).to eq("cher — 12 €") }
        it("trouve 10 € abordable ✓") { expect(Cafe.libellé(10)).to eq("abordable ✓") }
      end
    RUBY
  end

  def kimera(root, *args)
    command = ["bundle", "exec", "ruby", File.join(test_repo_root, "exe", "kimera"), *args].shelljoin
    gemfile = File.join(test_repo_root, "Gemfile").shellescape
    output = `cd #{root.shellescape} && env LANG=C LC_ALL=C BUNDLE_GEMFILE=#{gemfile} #{command} 2>&1`
    [output.force_encoding(Encoding::UTF_8), $CHILD_STATUS.exitstatus]
  end

  it "runs, reports and shows a mutant with UTF-8 names and source, at --jobs 2" do
    Dir.mktmpdir("kimera-locale") do |root|
      project(root)
      output, status = kimera(root, "run", "app", "--tests", "spec/**/*_spec.rb", "--jobs", "2", "--no-progress")
      expect(status).to(eq(0), output)
      report = JSON.parse(File.read(File.join(root, "tmp", "kimera", "report.json"), encoding: Encoding::UTF_8))
      expect(report["results"].map { |row| row["status"] }.uniq).to(eq(["killed"]))
      expect(report["tests"].values.map { |test| test["name"] }).to(include("Cafe trouve 12 € « cher »"))
      shown, = kimera(root, "mutant", "1")
      expect(shown).to(include("in libellé"))
    end
  end
end
