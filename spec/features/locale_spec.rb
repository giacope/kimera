# frozen_string_literal: true

require "English"
require "json"
require "shellwords"

RSpec.describe("kimera without a UTF-8 locale (end-to-end)", :aggregate_failures) do
  def menu
    <<~RUBY
      # Prix en euros
      module Cafe
        def self.libellé(prix) = prix > 10 ? "cher — \#{prix} €" : "abordable ✓"
      end
    RUBY
  end

  def examples
    <<~RUBY
      require_relative "../app/cafe"

      RSpec.describe Cafe do
        it("trouve 12 € « cher »") { expect(Cafe.libellé(12)).to eq("cher — 12 €") }
        it("trouve 5 € abordable ✓") { expect(Cafe.libellé(5)).to eq("abordable ✓") }
      end
    RUBY
  end

  def cli(root, locale, *arguments)
    command = ["bundle", "exec", "ruby", File.join(test_root, "exe", "kimera"), *arguments].shelljoin
    gemfile = File.join(test_root, "Gemfile").shellescape
    `cd #{root.shellescape} && env #{locale} BUNDLE_GEMFILE=#{gemfile} #{command} 2>&1`
      .force_encoding(Encoding::UTF_8).then { |text| [text, $CHILD_STATUS.exitstatus] }
  end

  def facts(root, locale)
    output, status = cli(root, locale, "run", "app", "--tests", "spec/**/*_spec.rb", "--jobs", "2", "--no-progress")
    expect(status).to(eq(2), output)
    report = JSON.parse(File.read(File.join(root, "tmp", "kimera", "report.json"), encoding: Encoding::UTF_8))
    {
      statuses: report["results"].map { |row| row["status"] }.uniq.sort,
      names: report["tests"].values.map { |test| test["name"] }
    }
  end

  def shown(root, locale) = [cli(root, locale, "report", "tmp/kimera/report.json"), cli(root, locale, "mutant", "1")]

  { "the C locale" => "LANG=C LC_ALL=C", "no locale" => "-u LANG -u LC_ALL -u LC_CTYPE" }.each do |name, locale|
    it "runs, reports and shows a mutant with UTF-8 names and source under #{name}, at --jobs 2" do
      test_tree({ "app/cafe.rb" => menu, "spec/cafe_spec.rb" => examples }, "kimera-locale") do |root|
        names = include("Cafe trouve 12 € « cher »")
        expect(facts(root, locale)).to(match(statuses: %w[killed survived], names: names))
        expect(shown(root, locale).map(&:first)).to(all(include("in libellé")))
      end
    end
  end
end
